# TBXark' blog

![](/assets/preview.png)


### Usage

The site has no third-party dependencies. Node.js 18 or newer is sufficient for
the local development and build scripts; no install step is required.

```bash
# NPM scripts
npm run dev      # Serve on localhost
npm run build    # Build the site (merge data + update SHA)
npm run preview  # Serve on localhost
npm run blogs    # Create /api/blogs.json
npm run projects # Create /api/repos.json
npm run merge    # Merge API data into /src/data.js
npm run lint     # Check JavaScript syntax

# Makefile commands (also dependency-free)
make preview # serve on localhost
make build # build the site for cloudflare page
make blogs # create /api/blogs.json
make projects # create /api/repos.json
```

### Architecture
- **No Runtime Fetch**: API data is pre-compiled into `/src/data.js` at build time
- **ES6 Modules**: Uses modern JavaScript module system for better performance
- **Build-time Optimization**: All JSON files are merged and embedded during build


### Feature
- Support `tab` to complete the command
- Support `up` and `down` to navigate the command history


### Support commands
```bash
pwd # current domain
ls # list supported commands
github # open github
weibo # open weibo
twitter # open twitter
blogs # list blogs
projects # list projects
```


### Links

Origin: https://www.tbxark.com

China Mirrors: https://www.tbxark.cn
