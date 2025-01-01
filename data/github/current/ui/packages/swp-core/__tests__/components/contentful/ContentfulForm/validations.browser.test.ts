import {describe, expect, it} from '@github-ui/tests'

import {getValidation} from '../../../../components/contentful/ContentfulForm/validations'

describe('Validations', () => {
  describe('REQUIRED', () => {
    const subject = getValidation({
      sys: {
        contentType: {
          sys: {
            id: 'formFieldValidation',
          },
        },
        id: '',
      },
      fields: {
        name: 'REQUIRED',
      },
    })

    it('rejects empty values', async () => {
      expect(subject.schema.safeParse('').success).toBe(false)
      expect(subject.schema.safeParse('   ').success).toBe(false)
    })

    it('accepts non-empty values', async () => {
      expect(subject.schema.safeParse('0').success).toBe(true)
    })
  })

  describe('WORK_EMAIL_ONLY', () => {
    const subject = getValidation({
      sys: {
        contentType: {
          sys: {
            id: 'formFieldValidation',
          },
        },
        id: '',
      },
      fields: {
        name: 'WORK_EMAIL_ONLY',
      },
    })

    it('rejects popular personal email providers', async () => {
      expect(subject.schema.safeParse('mona@gmail.com').success).toBe(false)
      expect(subject.schema.safeParse('mona@hotmail.co.uk').success).toBe(false)
      expect(subject.schema.safeParse('mona@hotmail.com').success).toBe(false)
      expect(subject.schema.safeParse('mona@yahoo.co.uk').success).toBe(false)
      expect(subject.schema.safeParse('mona@yandex.ru').success).toBe(false)
    })

    it('accepts email domains that are not from popular personal email providers', async () => {
      expect(subject.schema.safeParse('mona@github.com').success).toBe(true)
      expect(subject.schema.safeParse('mona@microsoft.com').success).toBe(true)
      expect(subject.schema.safeParse('mona@amazon.co.uk').success).toBe(true)
    })
  })

  describe('EMAIL', () => {
    const subject = getValidation({
      sys: {
        contentType: {
          sys: {
            id: 'formFieldValidation',
          },
        },
        id: '',
      },
      fields: {
        name: 'EMAIL',
      },
    })

    it('only accepts emails', async () => {
      expect(subject.schema.safeParse('').success).toBe(false)
      expect(subject.schema.safeParse('mona').success).toBe(false)
      expect(subject.schema.safeParse('mona@').success).toBe(false)
      expect(subject.schema.safeParse('mona@gmail.com').success).toBe(true)
    })
  })

  describe('PHONE', () => {
    const subject = getValidation({
      sys: {
        contentType: {
          sys: {
            id: 'formFieldValidation',
          },
        },
        id: '',
      },
      fields: {
        name: 'PHONE',
      },
    })

    it('only accepts valid phones', async () => {
      expect(subject.schema.safeParse('').success).toBe(false)
      expect(subject.schema.safeParse('333').success).toBe(false)
      expect(subject.schema.safeParse('+1 333').success).toBe(false)
      expect(subject.schema.safeParse('333 333 3333').success).toBe(false)
      expect(subject.schema.safeParse('+1 333 333 3333').success).toBe(true)
      expect(subject.schema.safeParse('+1 (333) 333 3333').success).toBe(true)
      expect(subject.schema.safeParse('+13333333333').success).toBe(true)
      expect(subject.schema.safeParse('+34 666 666 666').success).toBe(true)
      expect(subject.schema.safeParse('+34 666 666 6666').success).toBe(false)
      expect(subject.schema.safeParse('+34666666666').success).toBe(true)
    })
  })
})
