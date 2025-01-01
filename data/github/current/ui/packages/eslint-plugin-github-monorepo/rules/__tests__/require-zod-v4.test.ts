import {RuleTester} from 'eslint'
import rule from '../require-zod-v4'

// filepath: /workspaces/github/ui/packages/eslint-plugin-github-monorepo/rules/require-zod-v4.test.js

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('require-zod-v4', rule, {
  valid: [
    {
      code: `
// Importing from zod/v4 is correct
import { z } from 'zod/v4'
import zod from 'zod/v4'
import * as zodNamespace from 'zod/v4'

// Other imports should not be affected
import { useState } from 'react'
import React from 'react'

// Non-import statements should not be affected
const zodRequire = require('zod/v4')
      `,
    },
  ],
  invalid: [
    {
      name: "Default import from 'zod' should be flagged",
      code: "import z from 'zod'",
      errors: [{messageId: 'importZodV4'}],
      output: "import z from 'zod/v4'",
    },

    {
      name: "Named import from 'zod' should be flagged",
      code: "import { z } from 'zod'",
      errors: [{messageId: 'importZodV4'}],
      output: "import { z } from 'zod/v4'",
    },

    {
      name: "Namespace import from 'zod' should be flagged",
      code: "import * as z from 'zod'",
      errors: [{messageId: 'importZodV4'}],
      output: "import * as z from 'zod/v4'",
    },

    {
      name: 'Multiple imports with zod should flag only zod',
      code: "import z from 'zod'; import React from 'react';",
      errors: [{messageId: 'importZodV4'}],
      output: "import z from 'zod/v4'; import React from 'react';",
    },

    {
      name: 'Multiple named imports from zod should be flagged',
      code: "import { z, ZodSchema, ZodType } from 'zod'",
      errors: [{messageId: 'importZodV4'}],
      output: "import { z, ZodSchema, ZodType } from 'zod/v4'",
    },
  ],
})
