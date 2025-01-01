//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/testing/integration"
)

func Test_DeadLetter_Add_To_Dead_Letter_Queue_And_Reprocess(t *testing.T) {
	client, _ := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	// Make sure all queues are empty
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
	client.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateQueue(0, models.WorkerTypeHighWatermarkRolloverHandler)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeInvoiceGeneration)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeHighWatermarkRolloverHandler)

	// Produce some messages for the various queues
	client.ProduceBadMessageForQueue(models.WorkerTypeAzureEmission)
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)

	client.ProduceBadMessageForQueue(models.WorkerTypeInvoiceGeneration)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)

	client.ProduceBadMessageForQueue(models.WorkerTypeWatermarkHandler)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)

	client.ProduceBadMessageForQueue(models.WorkerTypeHighWatermarkRolloverHandler)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)

	// Run the queue workers
	// This consumes from the various queues and puts the bad messages on the dead letter queues
	client.RunAzureEmission(1)
	client.ValidateQueue(0, models.WorkerTypeAzureEmission)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeAzureEmission)

	client.RunInvoiceGeneration(1)
	client.ValidateQueue(0, models.WorkerTypeInvoiceGeneration)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeInvoiceGeneration)

	client.RunWatermarkHandler(1)
	client.ValidateQueue(0, models.WorkerTypeWatermarkHandler)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeWatermarkHandler)

	client.RunHighWatermarkRolloverHandler(1)
	client.ValidateQueue(0, models.WorkerTypeHighWatermarkRolloverHandler)
	client.ValidateDeadLetterQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)

	// Process the dead letter queues
	// This moves the bad messages from the dead letter queues back to the original queues
	_ = client.ProcessDeadLetterQueue(1, client.GetDeadLetterQueueName(models.WorkerTypeAzureEmission))
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeAzureEmission)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeAzureEmission)

	_ = client.ProcessDeadLetterQueue(1, client.GetDeadLetterQueueName(models.WorkerTypeInvoiceGeneration))
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeInvoiceGeneration)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeInvoiceGeneration)

	_ = client.ProcessDeadLetterQueue(1, client.GetDeadLetterQueueName(models.WorkerTypeWatermarkHandler))
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeWatermarkHandler)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeWatermarkHandler)

	_ = client.ProcessDeadLetterQueue(1, client.GetDeadLetterQueueName(models.WorkerTypeHighWatermarkRolloverHandler))
	client.RunRequestHandler(1)
	client.ValidateQueue(1, models.WorkerTypeHighWatermarkRolloverHandler)
	client.ValidateDeadLetterQueue(0, models.WorkerTypeHighWatermarkRolloverHandler)
}
