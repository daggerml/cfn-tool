.PHONY: all man

all: man

man: man/cfn-tool.1 man/cfn-tool.1.html

package-lock.json: package.json
	npm install

man/cfn-tool.1: cfn-tool.1.md package-lock.json
	npm run manroff

man/cfn-tool.1.html: cfn-tool.1.md package-lock.json
	npm run manhtml
