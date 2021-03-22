SHELL      := bash
VERSION    := $(shell cat package.json |jt version %)
DIRTY      := $(shell git status --untracked-files=no --porcelain)
TAG_EXISTS := $(shell git ls-remote --tags |awk '{print $$2}' |grep ^refs/tags/ |cut -d/ -f3- |grep $(VERSION))

.PHONY: all man test push

all: man test

man: man/cfn-tool.1 man/cfn-tool.1.html

test: package-lock.json
	npm test

push: man test
	[ -z "$(DIRTY)" ]
	[ -n "$(VERSION)" ]
	[ -z "$(TAG_EXISTS)" ]
	git tag $(VERSION)
	git push
	git push --tags

package-lock.json: package.json
	npm install

man/cfn-tool.1: cfn-tool.1.md package-lock.json
	npm run manroff

man/cfn-tool.1.html: cfn-tool.1.md package-lock.json
	npm run manhtml
