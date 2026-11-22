#!/usr/bin/env python3
""" Builds report.html: MaskCNN vs SUSformer comparison and combination, plus earlier experiments """
import base64
import pathlib

from build_report import bar_chart, coverage_chart, passes, exps, IMG

HERE = pathlib.Path(__file__).parent
VIEWS = IMG.with_name('views.jpg')

chart_passes = bar_chart(passes, 92, 96, ticks=(92, 93, 94, 95, 96), fmt='{:.1f}', hl={7})
chart_exps = bar_chart(exps, 93, 95.5, ticks=(93, 93.5, 94, 94.5, 95, 95.5), fmt='{:.2f}%', err=0.21, hl={2})
sus = [('1', 92.47), ('2', 96.70), ('3', 96.92), ('4', 96.98), ('5', 97.10), ('6', 97.09), ('7', 97.14), ('8', 97.08)]
chart_sus = bar_chart(sus, 90, 98, ticks=(90, 92, 94, 96, 98), fmt='{:.1f}', hl={6})
comb = [('As released', 85.08), ('MaskCNN', 95.83), ('SUSformer', 97.24), ('Both paved', 96.66),
        ('Either paved', 96.40), ('Average', 97.30), ('Both+tags', 97.57)]
chart_comb = bar_chart(comb, 80, 100, ticks=(80, 85, 90, 95, 100), fmt='{:.1f}', hl={2, 6})
cov = lambda v: list(zip((100, 95, 90, 80, 70, 50), v))
chart_cov = coverage_chart([
    ('ours', 'c-img', cov((95.83, 97.55, 98.45, 99.35, 99.66, 99.80))),
    ('sus', 'c-sus', cov((97.24, 98.71, 99.32, 99.72, 99.83, 99.90))),
    ('both', 'c-stk', cov((97.57, 98.92, 99.52, 99.86, 99.88, 99.93)))])

html = (HERE / 'template2.html').read_text()
for k, v in {'{{CHART_PASSES}}': chart_passes, '{{CHART_EXPS}}': chart_exps, '{{CHART_SUS_PASSES}}': chart_sus,
             '{{CHART_COMBINE}}': chart_comb, '{{CHART_COV}}': chart_cov,
             '{{ERRORS_IMG}}': base64.b64encode(IMG.read_bytes()).decode(),
             '{{VIEWS_IMG}}': base64.b64encode(VIEWS.read_bytes()).decode()}.items():
    assert k in html, k
    html = html.replace(k, v)
(HERE / 'report.html').write_text(html)
print('ok', len(html))
