#!/usr/bin/env python3
""" Builds report.html (paved/unpaved experiment report) with inline SVG charts """
import base64
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
from paths import DATA     # noqa: E402

IMG = DATA / 'report' / 'errors.jpg'     # error sheet + views.jpg next to it (data, not in git)


def bar_chart(items, lo, hi, w=640, h=230, fmt='{:.1f}%', err=None, hl=None, ticks=None):
    """ items: [(label, value)], vertical bars on a [lo, hi] axis """
    pl, pr, pt, pb = 46, 10, 14, 42
    iw, ih = w - pl - pr, h - pt - pb
    n = len(items)
    bw = iw / n * 0.62
    y = lambda v: pt + ih * (1 - (v - lo) / (hi - lo))
    out = [f'<svg viewBox="0 0 {w} {h}" role="img" class="chart">']
    for t in ticks:
        out.append(f'<line x1="{pl}" x2="{w - pr}" y1="{y(t):.1f}" y2="{y(t):.1f}" class="grid"/>'
                   f'<text x="{pl - 6}" y="{y(t) + 4:.1f}" class="tick" text-anchor="end">{t:g}%</text>')
    for i, (lab, v) in enumerate(items):
        cx = pl + iw / n * (i + 0.5)
        cls = 'bar hl' if hl is not None and i in hl else 'bar'
        out.append(f'<rect x="{cx - bw / 2:.1f}" y="{y(v):.1f}" width="{bw:.1f}" height="{y(lo) - y(v):.1f}" class="{cls}"/>')
        if err:
            out.append(f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="{y(v + err):.1f}" y2="{y(v - err):.1f}" class="err"/>'
                       f'<line x1="{cx - 6:.1f}" x2="{cx + 6:.1f}" y1="{y(v + err):.1f}" y2="{y(v + err):.1f}" class="err"/>'
                       f'<line x1="{cx - 6:.1f}" x2="{cx + 6:.1f}" y1="{y(v - err):.1f}" y2="{y(v - err):.1f}" class="err"/>')
        ty = y(v + (err or 0)) - 6
        out.append(f'<text x="{cx:.1f}" y="{ty:.1f}" class="val" text-anchor="middle">{fmt.format(v)}</text>')
        out.append(f'<text x="{cx:.1f}" y="{h - pb + 17}" class="lab" text-anchor="middle">{lab}</text>')
    out.append('</svg>')
    return ''.join(out)


def coverage_chart(series, w=640, h=260):
    pl, pr, pt, pb = 46, 16, 14, 40
    iw, ih = w - pl - pr, h - pt - pb
    xlo, xhi, ylo, yhi = 50, 100, 95, 100
    x = lambda v: pl + iw * (v - xlo) / (xhi - xlo)
    y = lambda v: pt + ih * (1 - (v - ylo) / (yhi - ylo))
    out = [f'<svg viewBox="0 0 {w} {h}" role="img" class="chart">']
    for t in (95, 96, 97, 98, 99, 100):
        out.append(f'<line x1="{pl}" x2="{w - pr}" y1="{y(t):.1f}" y2="{y(t):.1f}" class="grid"/>'
                   f'<text x="{pl - 6}" y="{y(t) + 4:.1f}" class="tick" text-anchor="end">{t}%</text>')
    for t in (50, 60, 70, 80, 90, 100):
        out.append(f'<text x="{x(t):.1f}" y="{h - pb + 18}" class="tick" text-anchor="middle">{t}%</text>')
    out.append(f'<text x="{pl + iw / 2:.1f}" y="{h - 4}" class="lab" text-anchor="middle">share of roads the model answers for (most confident first)</text>')
    out.append(f'<line x1="{x(80):.1f}" x2="{x(80):.1f}" y1="{pt}" y2="{y(ylo):.1f}" class="mark"/>')
    for name, cls, pts in series:
        d = ' '.join(f'{"M" if i == 0 else "L"}{x(a):.1f},{y(b):.1f}' for i, (a, b) in enumerate(pts))
        out.append(f'<path d="{d}" class="line {cls}" fill="none"/>')
        for a, b in pts:
            out.append(f'<circle cx="{x(a):.1f}" cy="{y(b):.1f}" r="3.5" class="dot {cls}"/>')
    out.append('</svg>')
    return ''.join(out)


passes = [('1', 93.62), ('2', 94.56), ('3', 94.06), ('4', 94.40), ('5', 95.06), ('6', 95.36), ('7', 95.47), ('8', 95.49)]
chart_passes = bar_chart(passes, 92, 96, ticks=(92, 93, 94, 95, 96), fmt='{:.1f}', hl={7})
exps = [('Past year', 94.49), ('±1 y of photo', 94.78), ('Random', 94.61), ('Cleaned', 94.63)]
chart_exps = bar_chart(exps, 93, 95.5, ticks=(93, 93.5, 94, 94.5, 95, 95.5), fmt='{:.2f}%', err=0.21, hl={2})
cov_img = [(100, 95.76), (95, 97.48), (90, 98.41), (80, 99.18), (70, 99.49), (50, 99.80)]
cov_stk = [(100, 96.41), (95, 98.16), (90, 98.94), (80, 99.61), (70, 99.79), (50, 99.86)]
chart_cov = coverage_chart([('image', 'c-img', cov_img), ('stack', 'c-stk', cov_stk)])

if __name__ == "__main__":
    img_b64 = base64.b64encode(IMG.read_bytes()).decode()

    html = (HERE / 'template.html').read_text()
    for k, v in {'{{CHART_PASSES}}': chart_passes, '{{CHART_EXPS}}': chart_exps,
                 '{{CHART_COV}}': chart_cov, '{{ERRORS_IMG}}': img_b64}.items():
        html = html.replace(k, v)
    (HERE / 'report.html').write_text(html)
    print('ok', len(html))
