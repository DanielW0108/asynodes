ifndef "$(ASYMPTOTE_HOME)"
ASYMPTOTE_HOME = ~/.asy
endif

install:
	mkdir $(ASYMPTOTE_HOME)/nodes
	cp -r * $(ASYMPTOTE_HOME)/nodes