package customerlabels

import (
	"strings"
)

const (
	Top100Label string = "top100"
	GitHubLabel string = "github"
	NoneLabel   string = "none"
)

type CustomerLabeler interface {
	LabelFor(owner string, enterpriseName string) string
}

type customerLabeler struct {
	labels               map[string]string
	fourNinesEnterprises map[string]bool
}

func NewCustomerLabeler(top100CustomersString string, temporaryFourNinesStageRolloutEnterpriseNames string) (CustomerLabeler, error) {
	labels := make(map[string]string)

	// This is an interim solution to get only top100 customer list from vault.
	// In long term we should get all label data from dotcom.

	top100Customers := getCustomersList(top100CustomersString)
	for _, customer := range top100Customers {
		labels[customer] = Top100Label
	}

	labels["github"] = GitHubLabel

	fourNinesMap := make(map[string]bool)
	for _, en := range getCustomersList(temporaryFourNinesStageRolloutEnterpriseNames) {
		fourNinesMap[en] = true
	}

	return &customerLabeler{
		labels:               labels,
		fourNinesEnterprises: fourNinesMap,
	}, nil
}

func getCustomersList(customersValues string) []string {
	var customerList []string

	customers := strings.Split(customersValues, ",")
	for _, customer := range customers {
		// Trim whitespaces and lowercase the customer name
		customerList = append(customerList, strings.ToLower(strings.TrimSpace(customer)))
	}

	return customerList
}

func (c *customerLabeler) LabelFor(owner string, enterpriseName string) string {
	enterpriseName = strings.ToLower(enterpriseName)
	org := strings.ToLower(owner)

	if enterpriseName != "" {
		if c.fourNinesEnterprises[enterpriseName] {
			return enterpriseName
		}
	}
	if label, ok := c.labels[org]; ok {
		return label
	}
	return ""
}

type noopCustomerLabeler struct{}

func NewNoopCustomerLabeler() CustomerLabeler {
	return &noopCustomerLabeler{}
}

func (c *noopCustomerLabeler) LabelFor(_ string, _ string) string {
	return ""
}

type CustomerLabelManifest struct {
}
