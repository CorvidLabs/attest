import { defineConfig } from 'astro/config'
import mdx from '@astrojs/mdx'
import sitemap from '@astrojs/sitemap'

function rewriteMdLinks() {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'link' && typeof node.url === 'string') {
        node.url = node.url.replace(/\.md(#|$)/, '$1')
      }
      if (node.children) node.children.forEach(visit)
    }
    visit(tree)
  }
}

export default defineConfig({
  site: 'https://corvidlabs.github.io',
  base: '/attest/',
  trailingSlash: 'never',
  integrations: [mdx(), sitemap()],
  markdown: {
    remarkPlugins: [rewriteMdLinks],
    shikiConfig: {
      // Dual themes so fenced code follows the page's light/dark mode.
      // Both are high-contrast variants that pass WCAG AA for token colors.
      // The .astro-code light/dark swap is wired in DocsLayout via CSS vars.
      themes: {
        light: 'github-light-high-contrast',
        dark: 'github-dark-high-contrast',
      },
    },
  },
})
