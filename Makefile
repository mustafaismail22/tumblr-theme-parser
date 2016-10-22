parser:
	./node_modules/.bin/pegjs < ./src/parser.pegjs > ./src/parser.js

build: parser
	cp -R src lib
	./node_modules/.bin/coffee -c lib
	find lib -iname "*.coffee" -exec rm '{}' ';'

unbuild:
	rm -rf lib

publish:
	make build
	npm publish .
	make unbuild
