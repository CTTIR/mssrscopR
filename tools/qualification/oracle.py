"""Independent scalar MSSR equation oracle for synthetic qualification.

No production R code is imported. Python's exact binary float inputs are lifted
to mpmath and evaluated with weighted absolute intensities, direct 16-tap 2D
interpolation, repeated reflection and accurate summation. This intentionally
uses different arithmetic from the conditioned vectorized production engine.
Run with Python 3 and mpmath==1.3.0; see README.md. No input data or network.
"""
import argparse
import csv
import hashlib
import itertools
import json
import math
import random
from pathlib import Path
import mpmath as mp


def reflect(j, n):
    while j < 0 or j >= n:
        j = -j - 1 if j < 0 else 2*n-j-1
    return j


def interpolation(frame, amp, grid):
    nr, nc = len(frame), len(frame[0])
    def coordinates(n):
        return [(mp.mpf(k)+mp.mpf('0.5'))/amp-mp.mpf('0.5')
                if grid == 'extent' else mp.mpf(k)*(n-1)/(n*amp-1)
                for k in range(n*amp)]
    def keys(t):
        t = abs(t)
        if t <= 1:
            return mp.mpf('1.5')*t**3-mp.mpf('2.5')*t**2+1
        if t < 2:
            return -mp.mpf('0.5')*t**3+mp.mpf('2.5')*t**2-4*t+2
        return mp.mpf(0)
    def point(y,x):
        fy,fx = int(mp.floor(y)),int(mp.floor(x))
        return mp.fsum(keys(y-r)*keys(x-c)*frame[reflect(r,nr)][reflect(c,nc)]
                       for r in range(fy-1,fy+3) for c in range(fx-1,fx+3))
    return [[point(y,x) for x in coordinates(nc)] for y in coordinates(nr)]


def oracle(frame, *, fwhm, amp, order, intensity_normalize, mesh, grid, kernel, rounding):
    a = [[mp.mpf(v) for v in row] for row in frame]
    nr,nc = len(a),len(a[0])
    if min(v for row in a for v in row) == max(v for row in a for v in row):
        return [[mp.mpf(0)]*(nc*amp) for _ in range(nr*amp)]
    # R's half-size arithmetic is binary64; this is the parameter contract,
    # not a decimal reinterpretation of the user-provided floating value.
    radius = 0.5*fwhm*amp
    hs = max(1, round(radius) if rounding == 'half_even' else math.floor(radius+0.5))
    if amp > 1:
        a = interpolation(a,amp,grid)
        nr,nc = len(a),len(a[0])
        if mesh:
            d = (amp+1)//2
            a = [[mp.fsum([a[r][c],a[reflect(r-d,nr)][c],a[reflect(r+d,nr)][c],
                          a[r][reflect(c-d,nc)],a[r][reflect(c+d,nc)]])/5
                  for c in range(nc)] for r in range(nr)]
    if max(v for row in a for v in row) <= 0:
        return [[mp.mpf(0)]*nc for _ in range(nr)]
    offsets=[(dr,dc) for dr in range(-hs,hs+1) for dc in range(-hs,hs+1)
             if (dr or dc) and (kernel == 'square' or dr*dr+dc*dc <= hs*hs)]
    spatial={(dr,dc):mp.exp(-mp.mpf(dr*dr+dc*dc)/(hs*hs)) for dr,dc in offsets}
    def shift(r,c):
        neighbors=[(dr,dc,a[reflect(r+dr,nr)][reflect(c+dc,nc)]) for dr,dc in offsets]
        local=max(abs(a[r][c]-v) for _,_,v in neighbors)
        weights=[(spatial[dr,dc]*mp.exp(-((a[r][c]-v)/local)**2 if local else 0),v)
                 for dr,dc,v in neighbors]
        return max(mp.mpf(0),a[r][c]-mp.fsum(w*v for w,v in weights)/mp.fsum(w for w,_ in weights))
    ms=[[shift(r,c) for c in range(nc)] for r in range(nr)]
    peak=max(v for row in ms for v in row)
    if peak <= 0:
        return [[mp.mpf(0)]*nc for _ in range(nr)]
    i=[[v/peak for v in row] for row in ms]
    peak_a=max(v for row in a for v in row)
    j=[[v/peak_a for v in row] for row in a]
    for _ in range(order):
        diff=[[u-v for u,v in zip(rj,ri)] for rj,ri in zip(j,i)]
        upper=max(v for row in diff for v in row)
        e=[[upper-v for v in row] for row in diff]
        peak_e=max(v for row in e for v in row)
        if peak_e <= 0:
            continue
        f=[[u/peak_e*v for u,v in zip(re,ri)] for re,ri in zip(e,i)]
        peak_f=max(v for row in f for v in row)
        j,i=i,[[v/peak_f if peak_f else v for v in row] for row in f]
    return [[u*v if intensity_normalize else u for u,v in zip(ri,ra)] for ri,ra in zip(i,a)]


def case_plan():
    scenes={
      'asymmetric':[[1.,11.,6.,3.],[4.,3.,9.,10.],[2.,5.,4.,5.]],
      'paired':[[.05,.05,.05,.05],[.05,2.05,.05,1.05],[.05,.05,.05,.05]],
      'edge':[[7.,7.,1.,1.],[7.,7.,1.,1.],[2.,2.,1.,1.]],
      'ramp':[[1.+r*.8+c*.3 for c in range(4)] for r in range(3)],
      'signed':[[-2.,1.,-1.,3.],[2.,-3.,0.,4.],[1.,-1.,2.,0.]],
      'near_flat':[[1.+v*2**-40 for v in row] for row in [[1,11,6,3],[4,3,9,10],[2,5,4,5]]]
    }
    combinations=list(itertools.product([1,2,3,4],['extent','endpoint'],['disk','square'],
                                       ['half_even','half_up'],[False,True],[False,True],[0,1,3,10]))
    rng=random.Random(20261024)
    rng.shuffle(combinations)
    cases=[]
    for k,(amp,grid,kernel,rounding,mesh,weighted,order) in enumerate(combinations[:80]):
        scene=list(scenes)[k%len(scenes)]
        # Alternate h=1.5 and h=2.5 boundaries with non-boundary h=1.3.
        radius=[1.5,2.5,1.3][k%3]
        cases.append(dict(id=f'option_{k:03d}',scenario=scene,frame=scenes[scene],fwhm=2*radius/amp,
            amp=amp,grid=grid,kernel=kernel,rounding=rounding,mesh=mesh,
            intensity_normalize=weighted,order=order))
    base=scenes['asymmetric']
    for exponent in [-1060,-1000,-500,500,1020]:
        for weighted in [False,True]:
            cases.append(dict(id=f'exponent_{exponent}_{int(weighted)}',scenario='binary_scale',
                frame=[[math.ldexp(v,exponent) for v in row] for row in base],
                fwhm=2.,amp=2,grid='extent',kernel='disk',rounding='half_even',mesh=True,
                intensity_normalize=weighted,order=3))
    for name,frame,amp,order in [
      ('large_background',[[2.**48+v for v in row] for row in base],3,3),
      ('flat',[[7.,7.],[7.,7.]],3,10),('zero',[[0.,0.],[0.,0.]],2,1),
      ('impulse',[[0.,0.,0.],[0.,1.,0.],[0.,0.,0.]],1,10),
      ('singleton_row',[[1.,3.,2.,5.]],3,3),('singleton_col',[[1.],[3.],[2.]],2,1),
      ('amplification8',[[1.,3.],[4.,2.]],8,1),
      ('dim_bright',[[1.,2.**-100,3.],[2.**-500,2.,4.]],2,3)]:
        cases.append(dict(id=name,scenario=name,frame=frame,fwhm=2/amp,amp=amp,grid='extent',
            kernel='square',rounding='half_up',mesh=False,intensity_normalize=False,order=order))
    return cases


def write_matrix(path, matrix):
    with path.open('w',newline='') as f:
        csv.writer(f).writerows([[mp.nstr(v,60) if isinstance(v,mp.mpf) else repr(v)
                                 for v in row] for row in matrix])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    cases=case_plan()
    params=['fwhm','amp','order','intensity_normalize','mesh','grid','kernel','rounding']
    plan={'oracle_version':'equations_scalar_v1','mpmath_version':mp.__version__,
          'precisions_decimal_digits':[100,160], 'hard_case_precision':220,
          'acceptance_normalized_max_error':1e-11,
          'pixelwise_mixed_rule':'abs(error)/peak <= 1e-11 + 1e-11*abs(expected)/peak + 2*smallest_subnormal/peak',
          'subnormal_ulp_allowance':2,'convergence_normalized_max_error':1e-70,
          'seed':20261024,'cases':[{k:v for k,v in c.items() if k!='frame'} for c in cases]}
    (args.output/'plan.json').write_text(json.dumps(plan,indent=2)+'\n')
    rows=[]
    for index,c in enumerate(cases):
        kw={k:c[k] for k in params}
        with mp.workdps(100): low=oracle(c['frame'],**kw)
        with mp.workdps(160):
            high=oracle(c['frame'],**kw)
            peak=max(abs(v) for row in high for v in row)
            err=max(abs(x-y) for rx,ry in zip(low,high) for x,y in zip(rx,ry))/(peak or 1)
            hard=c['scenario'] in ['near_flat','large_background','dim_bright','binary_scale']
            extra='not_run'
            if hard:
                with mp.workdps(220):
                    highest=oracle(c['frame'],**kw)
                    peak_extra=max(abs(v) for row in highest for v in row)
                    extra=mp.nstr(max(abs(x-y) for rx,ry in zip(high,highest)
                                      for x,y in zip(rx,ry))/(peak_extra or 1),12)
            write_matrix(args.output/(c['id']+'_input.csv'),c['frame'])
            write_matrix(args.output/(c['id']+'_expected.csv'),high)
            rows.append(dict(case=c['id'],error100_to160=mp.nstr(err,12),
                             error160_to220=extra,passed=bool(err<mp.mpf('1e-70') and (extra=='not_run' or mp.mpf(extra)<mp.mpf('1e-70')))))
        if (index+1)%20==0: print(f'Generated {index+1}/{len(cases)}',flush=True)
    with (args.output/'convergence.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
    assert all(r['passed'] for r in rows)
    (args.output/'files.sha256').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n'
        for p in sorted(args.output.iterdir()) if p.is_file() and p.name!='files.sha256'))
    print(f'PASS: {len(cases)} cases converged at 100/160 digits; hard cases also computed at 220 digits.')

if __name__=='__main__': main()
