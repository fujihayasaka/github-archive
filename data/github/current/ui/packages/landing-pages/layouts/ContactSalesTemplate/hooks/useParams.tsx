import {useEffect, useState} from 'react'

type ParamsProps = {
  ref_cta: string | null
  ref_loc: string | null
  ref_page: string | null
  utm_campaign: string | null
  utm_content: string | null
  utm_medium: string | null
  utm_source: string | null
  utm_term: string | null
  variant: string | null
}

export function useParams(): ParamsProps {
  const [params, setParams] = useState<ParamsProps>({
    ref_cta: null,
    ref_loc: null,
    ref_page: null,
    utm_campaign: null,
    utm_content: null,
    utm_medium: null,
    utm_source: null,
    utm_term: null,
    variant: null,
  })

  useEffect(() => {
    const url = new URLSearchParams(window.location.search)
    const ref_cta = url.get('ref_cta')
    const ref_loc = url.get('ref_loc')
    const ref_page = url.get('ref_page')
    const utm_campaign = url.get('utm_campaign')
    const utm_content = url.get('utm_content')
    const utm_medium = url.get('utm_medium')
    const utm_source = url.get('utm_source')
    const utm_term = url.get('utm_term')
    const variant = url.get('variant') ?? 'control'

    setParams({
      ref_cta,
      ref_loc,
      ref_page,
      utm_campaign,
      utm_content,
      utm_medium,
      utm_source,
      utm_term,
      variant,
    })
  }, [])

  return params
}
