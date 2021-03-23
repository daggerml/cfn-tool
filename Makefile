SHELL      = /bin/bash -o pipefail
VERSION    = $(shell cat package.json |jt version %)
BRANCH     = $(shell git symbolic-ref -q HEAD |grep ^refs/heads/ |cut -d/ -f3-)
DIRTY      = $(shell git status --untracked-files=no --porcelain)
TAG_EXISTS = $(shell git ls-remote --tags |awk '{print $$2}' |grep ^refs/tags/ |cut -d/ -f3- |grep $(VERSION))

.PHONY: all test docs push

all: docs test

docs: README.md man/cfn-tool.1 man/cfn-tool.1.html

test: package-lock.json
	npm test

push: all
	[ -n "$(VERSION)" ]
	[ -z "$(DIRTY)" ]
	[ -z "$(TAG_EXISTS)" ]
	[ master = "$(BRANCH)" ]
	git tag $(VERSION)
	git push
	git push --tags

package-lock.json: package.json
	npm install

README.md: README.in.md package-lock.json
	cat $< |VERSION=$(VERSION) envsubst '$${VERSION}' > $@

cfn-tool.1.md: cfn-tool.1.in.md package-lock.json
	cat $< |VERSION=$(VERSION) envsubst '$${VERSION}' > $@

man/cfn-tool.1: cfn-tool.1.md
	docker run --rm -v $(PWD):/app -w /app msoap/ruby-ronn \
		ronn -r --pipe --manual 'CloudFormation Tools' \
			--organization 'CloudFormation Tools $(VERSION)' $< > $@

man/cfn-tool.1.html: cfn-tool.1.md
	docker run --rm -v $(PWD):/app -w /app msoap/ruby-ronn \
		ronn -5 --pipe --manual 'CloudFormation Tools' --style=/app/cfn-tool.1.css \
			--organization 'CloudFormation Tools $(VERSION)' $< > $@
