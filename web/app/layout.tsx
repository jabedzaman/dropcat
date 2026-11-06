import type { Metadata } from "next";
import { IBM_Plex_Mono, IBM_Plex_Serif } from "next/font/google";
import "./globals.css";
import { SmoothScroll } from "./smooth-scroll";

const mono = IBM_Plex_Mono({ subsets: ["latin"], weight: ["400", "500"], variable: "--font-mono" });
const serif = IBM_Plex_Serif({ subsets: ["latin"], weight: ["400", "500"], style: ["normal", "italic"], variable: "--font-serif" });

export const metadata: Metadata = {
  title: "DropCat — your servers, in Finder",
  description:
    "A native macOS app for browsing remote machines over SSH and moving files with scp.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${mono.variable} ${serif.variable}`}>
      <body>
        <SmoothScroll />
        {children}
      </body>
    </html>
  );
}
