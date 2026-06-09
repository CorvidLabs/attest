import { defineCollection, z } from 'astro:content'

const docs = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string().optional(),
    section: z.enum(['Getting started', 'Reference', 'Signing & identity', 'Integrations']),
    order: z.number().int().nonnegative(),
  }),
})

export const collections = { docs }
