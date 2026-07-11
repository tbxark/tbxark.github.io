// <blog-terminal> — an encapsulated terminal-style blog UI (Shadow DOM Web Component).
// Reads its content from the globals populated by data.js: window.exes / blogs / repos.

const BLOG_HOST = 'https://github.com/TBXark/tbxark.github.io/blob/master/blog';

const MONO = `'SF Mono', ui-monospace, Menlo, Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace`;

const STYLES = `
  :host { display: block; }
  * { box-sizing: border-box; }

  .window {
    width: 80%;
    max-width: 750px;
    margin: 0 auto;
    background: #121212;
    border: 1px solid #282828;
    border-radius: 10px;
    overflow: hidden;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.55);
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
    padding: 0 14px;
    background: #161616;
    border-bottom: 1px solid #222222;
  }

  .dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #2a2a2a;
  }
  .dot:nth-child(1) { background: #ff5f57; }
  .dot:nth-child(2) { background: #febc2e; }
  .dot:nth-child(3) { background: #28c840; }

  .screen {
    min-height: 500px;
    max-height: 550px;
    overflow: auto;
    padding: 14px 16px 40px;
    font-family: ${MONO};
    font-size: 13px;
    line-height: 1.85;
    color: #ededed;
    scrollbar-width: none;
  }
  .screen::-webkit-scrollbar { display: none; }

  .cmd-text {
    margin: 2px 0;
    word-break: break-word;
  }

  .user { color: #3ecf8e; }
  .cmd { color: #cfcfcf; }
  .cmd.error { color: #9a9a9a; }

  .exe-list {
    display: flex;
    flex-wrap: wrap;
    gap: 18px;
    margin: 6px 0 12px;
  }

  a.exe,
  a.file {
    color: #3ecf8e;
    text-decoration: none;
    cursor: pointer;
  }
  a.exe:hover,
  a.file:hover { text-decoration: underline; }

  .perm,
  .date { color: #8f8f8f; }

  .blog-line {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* tree-style project row: fixed connector + name, description fills the rest */
  .project-line {
    display: flex;
    align-items: baseline;
    gap: 0.6ch;
  }
  .tree,
  .dash { flex: 0 0 auto; color: #6f7a72; }
  .proj-name {
    flex: 0 0 auto;
    white-space: nowrap;
  }
  .project-desc {
    flex: 1 1 auto;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    color: #8f8f8f;
  }

  .help strong { color: #3ecf8e; font-weight: 600; }
  .help-line { color: #b5b5b5; }

  .current {
    display: flex;
    align-items: center;
    margin-top: 4px;
  }
  .current .user { margin-right: 6px; }

  input.cmd-line {
    flex: 1;
    min-width: 0;
    padding: 0;
    margin: 0;
    border: none;
    outline: none;
    background: transparent;
    color: #3ecf8e;
    caret-color: #3ecf8e;
    font-family: ${MONO};
    font-size: 13px;
  }
  /* Emerald when it's a known command; neutral (still legible) for an unknown one. */
  input.cmd-line.error { color: #cfcfcf; }

  @media only screen and (max-width: 640px) {
    .window { width: calc(100% - 20px); }
    .full-mode { display: none; }
    .project-desc,
    .dash { display: none; }
  }
`;

// Tiny DOM builder — avoids innerHTML while keeping templates readable.
function h(tag, props, ...children) {
  const el = document.createElement(tag);
  if (props) {
    for (const [key, value] of Object.entries(props)) {
      if (value == null) continue;
      if (key === 'class') el.className = value;
      else if (key === 'text') el.textContent = value;
      else if (key === 'onclick') el.addEventListener('click', value);
      else el.setAttribute(key, value);
    }
  }
  for (const child of children.flat()) {
    if (child == null) continue;
    el.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return el;
}

class BlogTerminal extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.commands = {};
    this.history = [];
    this.historyIndex = 0;
    this.data = {
      exes: window.exes || [],
      blogs: window.blogs || [],
      repos: window.repos || [],
    };
  }

  connectedCallback() {
    this.renderShell();
    this.bindCommands();
    this.bindEvents();
    this.boot();
  }

  // ----- structure -----
  renderShell() {
    const style = document.createElement('style');
    style.textContent = STYLES;

    this.historyEl = h('div', { class: 'history' });
    this.inputEl = h('input', { class: 'cmd-line', autofocus: '', 'aria-label': 'terminal input' });

    this.screenEl = h(
      'div',
      { class: 'screen' },
      this.historyEl,
      h('div', { class: 'current' }, h('span', { class: 'user', text: 'guest@tbxark:~$' }), this.inputEl),
    );

    const window_ = h(
      'div',
      { class: 'window' },
      h('div', { class: 'bar' }, h('span', { class: 'dot' }), h('span', { class: 'dot' }), h('span', { class: 'dot' })),
      this.screenEl,
    );

    this.shadowRoot.append(style, window_);
  }

  // ----- output helpers -----
  print(node) {
    this.historyEl.append(node);
    this.screenEl.scrollTop = this.screenEl.scrollHeight;
  }

  printText(text) {
    this.print(h('div', { class: 'cmd-text', text }));
  }

  printPrompt(cmd, isError) {
    this.print(
      h(
        'div',
        { class: 'cmd-text' },
        h('span', { class: 'user', text: 'guest@tbxark:~$ ' }),
        h('span', { class: isError ? 'cmd error' : 'cmd', text: cmd }),
      ),
    );
  }

  // ----- element templates -----
  exeEl(e) {
    if (e.type === 'link') {
      return h('a', { class: 'exe', href: e.url }, e.name);
    }
    return h('a', { class: 'exe', onclick: () => this.run(e.name) }, e.name);
  }

  blogEl(b) {
    return h(
      'div',
      { class: 'cmd-text blog-line' },
      h('span', { class: 'perm full-mode', text: 'rw-r--r-- Tbxark ' }),
      h('span', { class: 'date', text: `${b.date.split(' ')[0]} ` }),
      h('a', { class: 'file', href: `${BLOG_HOST}/${b.fileName}`, text: b.title }),
    );
  }

  projectEl(p, index, list) {
    const isLast = index === list.length - 1;
    return h(
      'div',
      { class: 'cmd-text project-line' },
      h('span', { class: 'tree', text: isLast ? '└──' : '├──' }),
      h('a', { class: 'file proj-name', href: p.link, target: '_blank', rel: 'noopener', text: p.name }),
      h('span', { class: 'dash', text: '-' }),
      h('span', { class: 'project-desc', text: p.description }),
    );
  }

  // ----- commands -----
  bindCommands() {
    this.commands.clear = () => this.historyEl.replaceChildren();

    this.commands.pwd = () => this.printText(window.location.hostname);

    this.commands.help = () => {
      const line = (indent, name, desc) =>
        this.print(
          h(
            'div',
            { class: 'cmd-text help', style: `padding-left:${indent * 20}px` },
            h('strong', { text: name }),
            h('span', { class: 'help-line', text: desc }),
          ),
        );
      this.printText("Welcome to tbxark's blog!");
      this.printText('Usage:');
      line(1, 'ls', ' - list all commands');
      line(1, 'pwd', ' - show current location');
      line(1, 'clear', ' - clear screen');
      line(1, 'blogs', ' - list all blogs');
      line(2, '-p <page>', ' - page number (default: 0)');
      line(2, '-s <size>', ' - page size (default: all)');
      line(1, 'projects', ' - list all projects');
      line(2, '-p <page>', ' - page number (default: 0)');
      line(2, '-s <size>', ' - page size (default: all)');
      line(1, 'help', ' - show help');
    };

    this.commands.ls = () => {
      const list = h('div', { class: 'cmd-text exe-list' });
      for (const e of this.data.exes) list.append(this.exeEl(e));
      this.print(list);
    };

    this.commands.blogs = (args = {}) => {
      this.printPaged(this.data.blogs, args, (b) => this.blogEl(b), 'blogs');
    };

    this.commands.projects = (args = {}) => {
      this.printPaged(this.data.repos, args, (p, i, list) => this.projectEl(p, i, list), 'projects');
    };

    // Let link entries be typed/executed directly, e.g. `github`.
    for (const e of this.data.exes) {
      if (e.type === 'link') {
        this.commands[e.name] = () => {
          window.location = e.url;
        };
      }
    }
  }

  printPaged(items, args, toEl, label) {
    const page = parseInt(args.p || args.page || 0, 10);
    const size = parseInt(args.s || args.size || items.length, 10);
    const slice = items.slice(page * size, page * size + size);

    if (slice.length === 0) {
      this.printText(`No ${label} found for the specified page.`);
      return;
    }
    slice.forEach((item, i) => this.print(toEl(item, i, slice)));
    if (size < items.length) {
      const totalPages = Math.ceil(items.length / size);
      this.printText(`Showing page ${page + 1} of ${totalPages} (${slice.length} of ${items.length} ${label})`);
    }
  }

  // ----- input handling -----
  run(input) {
    if (!input || input.trim().length === 0) return;

    const { command, args } = parseArgs(input);
    const handler = this.commands[command];
    this.printPrompt(input, handler === undefined);

    this.history.push(input);
    this.historyIndex = 0;

    if (handler) handler(args);
    else this.printText(`command not found: ${command}`);
  }

  showHistory(isNext) {
    if (this.history.length === 0) return;
    this.historyIndex = (this.history.length + (isNext ? 1 : -1) + this.historyIndex) % this.history.length;
    this.inputEl.value = this.history[this.historyIndex];
    this.inputEl.selectionEnd = this.inputEl.value.length;
  }

  autoComplete() {
    const argv = this.inputEl.value;
    for (const c of Object.keys(this.commands)) {
      if (c.startsWith(argv)) {
        this.inputEl.value = c;
        break;
      }
    }
  }

  refreshInputState() {
    const { command } = parseArgs(this.inputEl.value);
    this.inputEl.classList.toggle('error', this.commands[command] === undefined);
  }

  bindEvents() {
    this.screenEl.addEventListener('click', () => this.inputEl.focus());
    this.inputEl.addEventListener('input', () => this.refreshInputState());
    this.inputEl.addEventListener('keydown', (e) => {
      switch (e.key) {
        case 'ArrowUp':
        case 'ArrowDown':
          this.showHistory(e.key === 'ArrowDown');
          this.refreshInputState();
          break;
        case 'Tab':
          e.preventDefault();
          this.autoComplete();
          this.refreshInputState();
          break;
        case 'Enter': {
          const argv = this.inputEl.value;
          this.inputEl.value = '';
          this.run(argv);
          this.refreshInputState();
          break;
        }
      }
    });
  }

  boot() {
    this.run('ls');
    this.run('blogs -p 0 -s 5');
    this.inputEl.focus();
  }
}

function parseArgs(cmd) {
  const parts = cmd.trim().split(/\s+/);
  const command = parts[0];
  const args = {};

  for (let i = 1; i < parts.length; i++) {
    if (parts[i].startsWith('-')) {
      const flag = parts[i].replace(/^-+/, '');
      if (i + 1 < parts.length && !parts[i + 1].startsWith('-')) {
        args[flag] = parts[i + 1];
        i++;
      }
    }
  }
  return { command, args };
}

customElements.define('blog-terminal', BlogTerminal);

// Page-level extras kept out of the component.
document.addEventListener('DOMContentLoaded', () => {
  if (document.location.host.indexOf('.cn') > 0) {
    const beian = document.getElementById('beian');
    if (beian) beian.style.display = 'block';
  }
});

console.log('This website is open source, you can find it on github: https://github.com/TBXark/tbxark.github.io');
