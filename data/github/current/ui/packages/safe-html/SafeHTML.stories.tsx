import type {Meta} from '@storybook/react'
import {type SafeHTMLString, SafeHTMLBox, SafeHTMLText, SafeHTMLDiv} from './SafeHTML'

const safeHTMLString =
  "This string has a <b>bold tag</b> and a <a class='Link--inTextBlock' href='https://github.com'>link</a> in it. It has been marked as safe." as SafeHTMLString

const meta = {
  title: 'Utilities/safe-html/SafeHTML',
} satisfies Meta

export default meta

export const Box = () => <SafeHTMLBox html={safeHTMLString} />

export const Text = () => <SafeHTMLText as="pre" html={safeHTMLString} />

export const Div = () => <SafeHTMLDiv html={safeHTMLString} />
