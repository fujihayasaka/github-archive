// @ts-check
const {client, v1} = require('@datadog/datadog-api-client')

class DataDog {
  /** @type {import('@datadog/datadog-api-client').v1.MetricsApi | undefined} */
  apiInstance
  /** @type {import('@datadog/datadog-api-client').client.Configuration | undefined} */
  configuration

  constructor() {
    if (!process.env.DX_TELEMETRY_DATADOG_API_KEY) return

    this.configuration = client.createConfiguration({
      authMethods: {
        apiKeyAuth: process.env.DX_TELEMETRY_DATADOG_API_KEY,
      },
    })
    this.apiInstance = new v1.MetricsApi(this.configuration)
  }

  /** @type {(metric: {name: string, value: number, tags: string[]}) => Promise<void>} */
  async distribution(metric) {
    if (!this.apiInstance) return

    /** @type {import('@datadog/datadog-api-client/dist/packages/datadog-api-client-v1').MetricsApiSubmitDistributionPointsRequest['body']} */
    const body = {
      series: [
        {
          metric: metric.name,
          points: [[Math.round(Date.now() / 1000), [metric.value]]],
          tags: metric.tags,
        },
      ],
    }

    try {
      await this.apiInstance.submitDistributionPoints({body})
    } catch (error) {
      console.error('Error submitting DataDog distribution metrics:', error)
    }
  }
}

module.exports.datadog = new DataDog()
