.PHONY: all man test

all: man test

man: man/cfn-tool.1 man/cfn-tool.1.html

test: package-lock.json
	npm test

package-lock.json: package.json
	npm install

man/cfn-tool.1: cfn-tool.1.md package-lock.json
	npm run manroff

man/cfn-tool.1.html: cfn-tool.1.md package-lock.json
	npm run manhtml
