SHELL      = /bin/bash -o pipefail
VERSION    = $(shell node version.js)
BRANCH     = $(shell git symbolic-ref -q HEAD |grep ^refs/heads/ |cut -d/ -f3-)
DIRTY      = $(shell git status --porcelain)
TAG_EXISTS = $(shell git ls-remote --tags |awk '{print $$2}' |grep ^refs/tags/ |cut -d/ -f3- |grep $(VERSION))
OBJS       = index.js $(shell find lib/ -name '*.coffee' |sed 's@coffee$$@js@')
MANS       = $(shell find man/ -name '*.in' |sed 's@in$$@1@')
HTMLS      = $(shell find man/ -name '*.in' |sed 's@in$$@html@')

.PHONY: all compile docs test push

all: compile docs test

compile: $(OBJS)

docs: README.md $(MANS) $(HTMLS)

test: compile package-lock.json
	npm test

push: all
	[ -n "$(VERSION)" ]
	[ -z "$(DIRTY)" ]
	[ -z "$(TAG_EXISTS)" ]
	[ master = "$(BRANCH)" ]
	git tag $(VERSION)
	git push
	git push --tags

# print variables (eg. make print-SHELL)
print-%:
	@echo '$($*)'

%.js: %.coffee
	npm run coffee -- --compile $<

%.md: %.in package-lock.json
	VERSION=$(VERSION) envsubst '$${VERSION}' < $< > $@

%.1: %.md
	docker run --rm -v $(PWD):/app -w /app msoap/ruby-ronn \
		ronn -r --pipe --manual 'CloudFormation Tools' \
			--organization 'CloudFormation Tools $(VERSION)' $< > $@

%.html: %.md cfn-tool.css
	docker run --rm -v $(PWD):/app -w /app msoap/ruby-ronn \
		ronn -5 --pipe --manual 'CloudFormation Tools' --style=/app/cfn-tool.css \
			--organization 'CloudFormation Tools $(VERSION)' $< > $@

package-lock.json: package.json
	npm install
