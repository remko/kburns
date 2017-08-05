KBURNS=./kburns.rb --dump-filter-graph

all:

.PHONY: tests
tests:
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/12x10.jpg ./tests/test--12x10--25fps--tli--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-out --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/12x10.jpg ./tests/test--12x10--25fps--tlo--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/12x10.jpg ./tests/test--12x10--25fps--bri--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-out --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/12x10.jpg ./tests/test--12x10--25fps--bro--crop_pan.mp4

	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/16x8.jpg ./tests/test--16x8--25fps--tli--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-out --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/16x8.jpg ./tests/test--16x8--25fps--tlo--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/16x8.jpg ./tests/test--16x8--25fps--bri--crop_pan.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-out --slide-duration=2 --fade-duration=0 --scale-mode=crop_pan ./tests/16x8.jpg ./tests/test--16x8--25fps--bro--crop_pan.mp4
	
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_center ./tests/12x10c.jpg ./tests/test--12x10--25fps--tli--crop_center.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-in --slide-duration=2 --fade-duration=0 --scale-mode=crop_center ./tests/12x10c.jpg ./tests/test--12x10--25fps--bri--crop_center.mp4
	
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/10x15.jpg ./tests/test--10x15--25fps--tli--pad.mp4

	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/16x8p.jpg ./tests/test--16x8--25fps--tli--pad.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-in --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/16x8p.jpg ./tests/test--16x8--25fps--bri--pad.mp4

	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/12x10p.jpg ./tests/test--12x10--25fps--tli--pad.mp4
	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=bottom-right-in --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/12x10p.jpg ./tests/test--12x10--25fps--bri--pad.mp4

	$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=top-left-in --slide-duration=3 --fade-duration=1 --scale-mode=pad ./tests/16x10.jpg ./tests/16x8p.jpg ./tests/12x10p.jpg ./tests/test--fade.mp4

	for x in left center right; do \
		for y in top center bottom; do \
			for z in in out; do \
				set -x; \
				$(KBURNS) --fps=25 --zoom-rate=0.25 --zoom-direction=$$y-$$x-$$z --slide-duration=2 --fade-duration=0 --scale-mode=pad ./tests/16x10.jpg ./tests/test--16x10--25fps--$$(echo $$y | head -c 1)$$(echo $$x | head -c 1)$$(echo $$z | head -c 1)--pad.mp4 || exit -1; \
				set +x; \
			done; \
		done; \
	done

.PHONY: clean
clean:
	-rm -rf tests/test-*.mp4 tests/test-*.png
