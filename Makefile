.PHONY: preview, blogs, projects, build

preview:
	node ./bin/preview.js

blogs:
	node ./bin/blogs.js

projects:
	node ./bin/repos.js

build:
	node ./bin/merge.js
	node ./bin/build.js
