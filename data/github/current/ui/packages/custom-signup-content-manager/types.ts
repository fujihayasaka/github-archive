export type CustomSignupContentPage = {
  url_param: string
  title: string
  page_content: string
  background_image_url?: string | null
  background_image_alt_text?: string | null
  foreground_image_url?: string | null
  foreground_image_alt_text?: string | null
  enable_page_stepper: boolean
  published: boolean
}
