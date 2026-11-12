// Entry point for the build script in your package.json

import './channels'
import './custom/index'
import Rails from '@rails/ujs'
import { start as activestorage_start } from '@rails/activestorage'
import { start as turbolinks_start } from 'turbolinks'

turbolinks_start()
Rails.start()
activestorage_start()
