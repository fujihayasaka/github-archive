import {all} from 'lowlight'
// eslint-disable-next-line no-restricted-imports
import hljs from 'highlight.js/lib/core'

// Reusing `all` from `lowlight` ensures that we use the languages from `highlight.js/lib/languages/*` instead of the
// default from `/highlight.js/es/languages/*` if we just used the default registered languages.
// The default would be fine if we are only using highlight.js, but because we also use lowlight, it causes the bundle
// size to explode. By reusing what lowlight uses we can ensure this doesn't happen, saving at least a megabyte of
// bundle size.
for (const [name, language] of Object.entries(all)) {
  hljs.registerLanguage(name, language)
}

// eslint-disable-next-line no-barrel-files/no-barrel-files
export default hljs
