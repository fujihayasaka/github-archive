// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
'use strict'

/**
 * validateMcpSchema - standalone Ajv-generated validation function
 * This file is safe to include in your project without Ajv as a runtime dependency
 */

const pattern0 = new RegExp('^[a-zA-Z0-9_-]+$', 'u')

// eslint-disable-next-line unused-imports/no-unused-vars
function validateMcpSchema(data, {instancePath = '', parentData, parentDataProperty, rootData = data} = {}) {
  const vErrors = null
  const errors = 0

  // Root must be an object
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    if (Object.keys(data).some(key => key !== 'mcpServers')) {
      validateMcpSchema.errors = [
        {
          instancePath,
          schemaPath: '#/additionalProperties',
          keyword: 'additionalProperties',
          params: {additionalProperty: Object.keys(data).find(k => k !== 'mcpServers')},
          message: 'must NOT have additional properties',
        },
      ]
      return false
    }

    const data0 = data.mcpServers
    if (data0 && typeof data0 === 'object' && !Array.isArray(data0)) {
      for (const key of Object.keys(data0)) {
        if (!pattern0.test(key)) {
          validateMcpSchema.errors = [
            {
              instancePath: `${instancePath}/mcpServers`,
              schemaPath: '#/properties/mcpServers/additionalProperties',
              keyword: 'additionalProperties',
              params: {additionalProperty: key},
              message: 'must NOT have additional properties',
            },
          ]
          return false
        }

        const config = data0[key]
        if (!config || typeof config !== 'object' || Array.isArray(config)) {
          validateMcpSchema.errors = [
            {
              instancePath: `${instancePath}/mcpServers/${key}`,
              schemaPath: '#/properties/mcpServers/patternProperties/.../type',
              keyword: 'type',
              params: {type: 'object'},
              message: 'must be object',
            },
          ]
          return false
        }

        for (const prop of ['command', 'args', 'tools']) {
          if (!(prop in config)) {
            validateMcpSchema.errors = [
              {
                instancePath: `${instancePath}/mcpServers/${key}`,
                schemaPath: '#/properties/mcpServers/.../required',
                keyword: 'required',
                params: {missingProperty: prop},
                message: `must have required property '${prop}'`,
              },
            ]
            return false
          }
        }

        const {command, type, args, tools, env, ...rest} = config

        if (typeof command !== 'string') return fail(`${instancePath}/mcpServers/${key}/command`, 'string')
        if (type !== undefined) {
          if (typeof type !== 'string') return fail(`${instancePath}/mcpServers/${key}/type`, 'string')
          if (type !== 'local') {
            validateMcpSchema.errors = [
              {
                instancePath: `${instancePath}/mcpServers/${key}/type`,
                schemaPath: '#/properties/mcpServers/.../enum',
                keyword: 'enum',
                params: {allowedValues: ['local']},
                message: `must be 'local'`,
              },
            ]
            return false
          }
        }
        if (!Array.isArray(args) || !args.every(a => typeof a === 'string'))
          return fail(`${instancePath}/mcpServers/${key}/args`, 'array of strings')
        if (!Array.isArray(tools) || !tools.every(t => typeof t === 'string'))
          return fail(`${instancePath}/mcpServers/${key}/tools`, 'array of strings')
        if (env !== undefined) {
          if (!env || typeof env !== 'object' || Array.isArray(env))
            return fail(`${instancePath}/mcpServers/${key}/env`, 'object')
          for (const [k, v] of Object.entries(env)) {
            if (typeof v !== 'string') return fail(`${instancePath}/mcpServers/${key}/env/${k}`, 'string')
          }
        }

        if (Object.keys(rest).length > 0) {
          validateMcpSchema.errors = [
            {
              instancePath: `${instancePath}/mcpServers/${key}`,
              schemaPath: '#/properties/mcpServers/.../additionalProperties',
              keyword: 'additionalProperties',
              params: {additionalProperty: Object.keys(rest)[0]},
              message: 'must NOT have additional properties',
            },
          ]
          return false
        }
      }
    } else {
      return fail(`${instancePath}/mcpServers`, 'object')
    }
  } else {
    return fail(instancePath, 'object')
  }

  validateMcpSchema.errors = vErrors
  return errors === 0

  function fail(path, expectedType) {
    validateMcpSchema.errors = [
      {
        instancePath: path,
        schemaPath: '#',
        keyword: 'type',
        params: {type: expectedType},
        message: `must be ${expectedType}`,
      },
    ]
    return false
  }
}
export default validateMcpSchema
