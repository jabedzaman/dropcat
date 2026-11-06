import Image from "next/image";

const REPO = "https://github.com/jabedzaman/dropcat";
const RELEASE = `${REPO}/releases/latest`;

// Swap for your recorded demo (put the file in web/public/, e.g. "/demo.gif").
const DEMO_SRC = "/app.png";

const pillars: [string, string][] = [
  ["Native", "Built for macOS. Uses your system ssh and scp, nothing bundled."],
  ["Familiar", "Finder-style list and icon views. Press space for Quick Look."],
  ["Private", "Your keys, your agent. Nothing to install on the server."],
];

const tiles: [string, string][] = [
  ["Machines", "A sidebar with status dots, favorites and per-machine state."],
  ["Two views", "List or icon view, with tree expansion in the list."],
  ["Drag to upload", "Drop files in from Finder. scp does the transfer."],
  ["Quick Look", "Preview remote files with the space bar."],
  ["Edit in place", "Inline rename, new folder and delete."],
  ["Your ssh config", "~/.ssh/config only pre-fills or imports hosts."],
];

export default function Home() {
  return (
    <div className="page">
      <header className="nav">
        <a className="brand" href="#">
          <Image src="/icon.png" alt="" width={22} height={22} />
          DropCat
        </a>
        <nav>
          <a href="#features">Features</a>
          <a href={REPO}>GitHub</a>
        </nav>
        <a className="btn sm" href={RELEASE}>
          Download
        </a>
      </header>

      <div className="news">
        DropCat 0.1 is in beta. <a href={RELEASE}>Try it today →</a>
      </div>

      <section className="hero">
        <h1>Your servers, in Finder.</h1>
        <p>
          DropCat is a native Mac app for browsing remote machines over SSH
          and moving files with scp.
        </p>
        <div className="actions">
          <a className="btn" href={RELEASE}><span aria-hidden>↓</span> Download now</a>
          <a className="btn ghost" href={REPO}>View source</a>
        </div>
        <small>Available for macOS 15 and later.</small>
      </section>

      <section className="pillars" id="features">
        {pillars.map(([k, v]) => (
          <div key={k}>
            <h3>{k}</h3>
            <p>{v}</p>
          </div>
        ))}
      </section>

      <section className="demo">
        <div className="demo-frame">
          <Image src={DEMO_SRC} alt="DropCat demo" width={1013} height={725} unoptimized priority />
        </div>
      </section>

      <section className="head">
        <div>
          <h2>DropCat just works</h2>
          <p>Connect to a host, browse it like a folder, move files.</p>
        </div>
        <a className="btn ghost sm" href={REPO}>View source ↗</a>
      </section>

      <section className="tiles">
        {tiles.map(([k, v]) => (
          <div key={k}>
            <h3>{k}</h3>
            <p>{v}</p>
          </div>
        ))}
      </section>

      <section className="center">
        <h2>Open source</h2>
        <p>DropCat is MIT licensed. Read the code, file an issue, send a patch.</p>
        <a className="btn ghost" href={REPO}>GitHub ↗</a>
      </section>

      <footer>
        <span>MIT · Cat icon by <a href="https://icons8.com">Icons8</a></span>
        <a href={REPO}>GitHub</a>
      </footer>
    </div>
  );
}
