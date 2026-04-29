import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DOCS_DIR = fileURLToPath(new URL('../content/docs/', import.meta.url));

function entryToSlug(id: string): string {
  let slug = id.replace(/\.(mdx?|markdown)$/, '');
  if (slug.endsWith('/index')) slug = slug.slice(0, -'/index'.length);
  if (slug === 'index') slug = '';
  return slug;
}

export async function getStaticPaths() {
  const entries = await getCollection('docs');
  return entries
    .map((entry) => ({
      params: { slug: entryToSlug(entry.id) },
      props: { sourcePath: entry.filePath ?? path.join(DOCS_DIR, entry.id) },
    }))
    .filter((p) => p.params.slug !== '');
}

export const GET: APIRoute = async ({ props }) => {
  const { sourcePath } = props as { sourcePath: string };
  const raw = await fs.readFile(sourcePath, 'utf8');
  return new Response(raw, {
    headers: {
      'Content-Type': 'text/markdown; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
};
