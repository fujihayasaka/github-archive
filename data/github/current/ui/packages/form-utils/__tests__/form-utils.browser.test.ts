import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {changeValue, isFormField, requestSubmit} from '../form-utils'

describe('Form helpers', function () {
  let form: HTMLFormElement

  beforeEach(async function () {
    form = await fixture(html`
      <form data-turbo="false">
        <input type="checkbox" name="checkbox">
        <input type="text" name="text">
        <textarea name="textarea"></textarea>
      </div>
    `)
  })

  it('submit allowed', function () {
    let submitFired = false
    form.addEventListener('submit', () => {
      submitFired = true
    })

    let submitInvoked = false
    form.submit = function () {
      submitInvoked = true
    }

    requestSubmit(form)
    assert.isTrue(submitFired)
    assert.isTrue(submitInvoked)
  })

  it('submit prevented', function () {
    let submitFired = false
    form.addEventListener('submit', event => {
      submitFired = true
      event.preventDefault()
    })

    let submitInvoked = false
    form.submit = function () {
      submitInvoked = true
    }

    requestSubmit(form)
    assert.isTrue(submitFired)
    assert.isFalse(submitInvoked)
  })

  it('changeValue text field', function () {
    const field = form.querySelector('input[type=text]') as HTMLInputElement

    let changeTarget
    form.addEventListener('change', event => {
      changeTarget = event.target
    })

    changeValue(field, 'Hello!')
    assert.equal(field.value, 'Hello!')
    assert.strictEqual(changeTarget, field)
  })

  it('changeValue checkbox', function () {
    const field = form.querySelector('input[type=checkbox]') as HTMLInputElement

    let changeTarget
    form.addEventListener('change', event => {
      changeTarget = event.target
    })

    changeValue(field, true)
    assert.isTrue(field.checked)
    assert.strictEqual(changeTarget, field)
  })

  it('changeValue textarea', function () {
    const field = form.querySelector('textarea') as HTMLTextAreaElement

    let changeTarget
    form.addEventListener('change', event => {
      changeTarget = event.target
    })

    changeValue(field, 'Hello!')
    assert.equal(field.value, 'Hello!')
    assert.strictEqual(changeTarget, field)
  })
})

describe('isFormField helper', function () {
  it('DIV element is not form interaction', function () {
    const el = document.createElement('div')
    assert.isFalse(isFormField(el))
  })

  it('INPUT field is form interaction', function () {
    const el = document.createElement('input')
    assert.isTrue(isFormField(el))
  })

  it('INPUT[type=text] field is form interaction', function () {
    const el = document.createElement('input')
    el.type = 'text'
    assert.isTrue(isFormField(el))
  })

  it('INPUT[type=search] field is form interaction', function () {
    const el = document.createElement('input')
    el.type = 'search'
    assert.isTrue(isFormField(el))
  })

  it('INPUT[type=submit] button is not form interaction', function () {
    const el = document.createElement('input')
    el.type = 'submit'
    assert.isFalse(isFormField(el))
  })

  it('INPUT[type=reset] button is not form interaction', function () {
    const el = document.createElement('input')
    el.type = 'reset'
    assert.isFalse(isFormField(el))
  })

  it('BUTTON is not form interaction', function () {
    const el = document.createElement('button')
    assert.isFalse(isFormField(el))
  })

  it('TEXTAREA is form interaction', function () {
    const el = document.createElement('textarea')
    assert.isTrue(isFormField(el))
  })

  it('SELECT box is form interaction', function () {
    const el = document.createElement('select')
    assert.isTrue(isFormField(el))
  })
})
