import {z} from 'zod/v4'

import {buildPageSchemaForTemplate} from '@github-ui/swp-core/schemas/contentful/contentTypes/containerPage'
import {FlexPageSchema} from '@github-ui/swp-core/schemas/contentful/contentTypes/flexTemplate'

import {TemplateContactSalesSchema} from './templateContactSales'
import {TemplateF2Schema} from './templateF2'
import {TemplateFreeFormSchema} from './templateFreeForm'
import {TemplateUniverse23WaitlistSchema} from './templateUniverse23Waitlist'

const FreeFormPageSchema = buildPageSchemaForTemplate(TemplateFreeFormSchema)
export type FreeFormPage = z.infer<typeof FreeFormPageSchema>

const Universe23WaitlistPageSchema = buildPageSchemaForTemplate(TemplateUniverse23WaitlistSchema)
export type Universe23WaitlistPage = z.infer<typeof Universe23WaitlistPageSchema>

const ContactSalesPageSchema = buildPageSchemaForTemplate(TemplateContactSalesSchema)
export type ContactSalesPage = z.infer<typeof ContactSalesPageSchema>

const F2PageSchema = buildPageSchemaForTemplate(TemplateF2Schema)
export type F2Page = z.infer<typeof F2PageSchema>

const ContainerPageSchema = z.union([
  ContactSalesPageSchema,
  F2PageSchema,
  FlexPageSchema,
  FreeFormPageSchema,
  Universe23WaitlistPageSchema,
])

export type ContainerPage = z.infer<typeof ContainerPageSchema>
export function toContainerPage(item: unknown): ContainerPage {
  return ContainerPageSchema.parse(item)
}
