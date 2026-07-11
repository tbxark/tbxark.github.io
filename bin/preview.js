import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const port = Number.parseInt(process.env.PORT || '23400', 10);
const host = process.env.HOST || '127.0.0.1';

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.gif': 'image/gif',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

const server = createServer((request, response) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { Allow: 'GET, HEAD' });
    response.end('Method Not Allowed');
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, `http://${request.headers.host || host}`).pathname);
  } catch {
    response.writeHead(400);
    response.end('Bad Request');
    return;
  }

  let file = resolve(root, `.${pathname}`);
  if (file !== root && !file.startsWith(`${root}${sep}`)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }

  try {
    if (statSync(file).isDirectory()) file = resolve(file, 'index.html');
    const stat = statSync(file);
    if (!stat.isFile()) throw new Error('Not a file');

    response.writeHead(200, {
      'Content-Length': stat.size,
      'Content-Type': contentTypes[extname(file).toLowerCase()] || 'application/octet-stream',
    });
    if (request.method === 'HEAD') response.end();
    else createReadStream(file).pipe(response);
  } catch {
    response.writeHead(404);
    response.end('Not Found');
  }
});

server.listen(port, host, () => {
  console.log(`Serving ${root} at http://${host}:${port}`);
});
