package models

import (
	"fmt"
	"regexp"
)

const (
	products = "actions|codespaces|copilot|ghas|ghec|git_lfs|packages"
)

func (key *Key) GetProductFromPartitionKey() string {
	pattern := regexp.MustCompile(fmt.Sprintf(`\b(%s)`, products))
	return pattern.FindString(key.PartitionKey)
}

func (key *Key) GetProductFromKeyId() string {
	pattern := regexp.MustCompile(fmt.Sprintf(`\b(%s)`, products))
	return pattern.FindString(key.Id)
}

func (key *Key) GetProductSkuFromPartitionKey() string {
	pattern := regexp.MustCompile(fmt.Sprintf(`\b(%s)_\w+`, products))
	return pattern.FindString(key.PartitionKey)
}

func (key *Key) GetPartitionTemplate() string {
	partitionKey := key.PartitionKey
	partitionKey = replaceUuid(partitionKey)
	partitionKey = replaceCustomerID(partitionKey)
	partitionKey = replaceOrgId(partitionKey)
	partitionKey = replaceOwningEntity(partitionKey)
	partitionKey = replaceEnterpriseId(partitionKey)
	partitionKey = replaceRepoId(partitionKey)
	partitionKey = replaceProductName(partitionKey)
	partitionKey = replaceProductSkuName(partitionKey)

	// datetime order is important as the replacement is using the previous replacement
	// YYYY -> YYYY:MM -> YYYY:MM:DD -> YYYY:MM:DD:HH
	partitionKey = replaceYear(partitionKey)
	partitionKey = replaceMonth(partitionKey)
	partitionKey = replaceDay(partitionKey)
	partitionKey = replaceHour(partitionKey)

	partitionKey = replaceNumber(partitionKey)

	return partitionKey
}

func replaceUuid(partitionKey string) string {
	pattern := regexp.MustCompile(`\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "uuid")

	pattern = regexp.MustCompile(`\b[0-9a-f]{64}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "uuid")

	return partitionKey
}

func replaceCustomerID(partitionKey string) string {
	pattern := regexp.MustCompile(`\bcustomer:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "customer:customerID")
	pattern = regexp.MustCompile(`^\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "customerID")

	return partitionKey
}

func replaceEnterpriseId(partitionKey string) string {
	pattern := regexp.MustCompile(`\benterprise:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "enterprise:businessID")

	return partitionKey
}

func replaceOrgId(partitionKey string) string {
	pattern := regexp.MustCompile(`\borg:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "org:orgID")

	pattern = regexp.MustCompile(`\borganization:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "organization:orgID")

	return partitionKey
}

func replaceOwningEntity(partitionKey string) string {
	pattern := regexp.MustCompile(`\bowning_entity:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "owning_entity:entityID")

	return partitionKey
}

func replaceRepoId(partitionKey string) string {
	pattern := regexp.MustCompile(`\brepo:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "repo:repoID")

	pattern = regexp.MustCompile(`\brepository:\d+`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "repository:repoID")

	return partitionKey
}

func replaceProductName(partitionKey string) string {
	pattern := regexp.MustCompile(fmt.Sprintf(`\b(%s)\b`, products))
	partitionKey = pattern.ReplaceAllString(partitionKey, "productName")

	return partitionKey
}

func replaceProductSkuName(partitionKey string) string {
	pattern := regexp.MustCompile(fmt.Sprintf(`\b(%s)_\w+`, products))
	partitionKey = pattern.ReplaceAllString(partitionKey, "skuName")

	return partitionKey
}

func replaceYear(partitionKey string) string {
	pattern := regexp.MustCompile(`\b20\d{2}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "YYYY")

	return partitionKey
}

func replaceMonth(partitionKey string) string {
	pattern := regexp.MustCompile(`\bYYYY:\d{1,2}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "YYYY:MM")

	return partitionKey
}

func replaceDay(partitionKey string) string {
	pattern := regexp.MustCompile(`\bYYYY:MM:\d{1,2}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "YYYY:MM:DD")

	return partitionKey
}

func replaceHour(partitionKey string) string {
	pattern := regexp.MustCompile(`\bYYYY:MM:DD:\d{1,2}\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "YYYY:MM:DD:HH")

	return partitionKey
}

func replaceNumber(partitionKey string) string {
	pattern := regexp.MustCompile(`\b\d+\b`)
	partitionKey = pattern.ReplaceAllString(partitionKey, "xxx")

	return partitionKey
}
