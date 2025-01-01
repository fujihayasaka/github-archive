const FOOTNOTE_ID_BASE = 'footnote_'

export const getFootnoteId = (number: number) => `${FOOTNOTE_ID_BASE}${number}`
export const getFootnoteNumberFromId = (id: string) => parseInt(id.replace(FOOTNOTE_ID_BASE, ''))
export const isFootnoteId = (id: string) => !!id.match(new RegExp(`^${FOOTNOTE_ID_BASE}\\d+$`))
