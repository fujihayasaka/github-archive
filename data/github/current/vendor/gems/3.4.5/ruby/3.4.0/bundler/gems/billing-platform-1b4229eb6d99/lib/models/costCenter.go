package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
	"github.com/pkg/errors"
)

type CostCenterType byte

const (
	NoCostCenter CostCenterType = iota
	GitHubEnterpriseCustomer
	ZuoraSubscription
	CreditCard
	AzureSubscription
)

var ErrorCostCenterConflict = errors.New("conflict")

func ToCostCenterType(t proto.CostCenterType) CostCenterType {
	return CostCenterType(t)
}

func (b CostCenterType) ToProto() proto.CostCenterType {
	return proto.CostCenterType(b)
}

func (b CostCenterType) String() string {
	switch b {
	case GitHubEnterpriseCustomer:
		return "github_enterprise_customer"
	case ZuoraSubscription:
		return "zuora_subscription"
	case CreditCard:
		return "credit_card"
	case AzureSubscription:
		return "azure_subscription"
	default:
		return fmt.Sprintf("%d", int(b))
	}
}

type CostCenterState byte

const (
	CostCenterActive CostCenterState = iota
	CostCenterArchived
)

func (c CostCenterState) String() string {
	switch c {
	case CostCenterActive:
		return "Active"
	case CostCenterArchived:
		return "Archived"
	default:
		return fmt.Sprintf("%d", int(c))
	}
}

type CostCenterKey struct {
	*Key
	Customer   *Customer // the parent enterprise
	TargetType CostCenterType
	TargetId   string
	UUID       string
}

type CostCenter struct {
	*CostCenterKey
	Name            string
	Resources       []*Resource
	CostCenterState CostCenterState

	// Store this value for performance when validating resource uniqueness
	resourcesMap map[ResourceType]map[string]bool
}

func (c *CostCenterKey) ToProto() *proto.CostCenterKey {
	return &proto.CostCenterKey{
		CustomerId: c.Customer.GetCustomerId(),
		TargetType: c.TargetType.ToProto(),
		TargetId:   c.TargetId,
		Uuid:       c.UUID,
	}
}

func (c *CostCenter) ToProto() *proto.CostCenter {
	resources := make([]*proto.Resource, len(c.Resources))
	for i, r := range c.Resources {
		resources[i] = r.ToProto()
	}

	return &proto.CostCenter{
		CostCenterKey:   c.CostCenterKey.ToProto(),
		Name:            c.Name,
		Resources:       resources,
		CostCenterState: c.CostCenterState.ToProto(),
	}
}

func (c CostCenterState) ToProto() proto.CostCenterState {
	return proto.CostCenterState(c)
}

func (c *CostCenterKey) AsTargetType() *CostCenterKey {
	copy := *c
	copy.Key = &Key{
		PartitionKey: copy.PartitionKey,
		Id:           fmt.Sprintf("byTarget:%s:%s", c.TargetType, c.TargetId),
	}

	return &copy
}
func (c *CostCenterKey) AsUUID() *CostCenterKey {
	copy := *c
	copy.Key = &Key{
		PartitionKey: copy.Customer.ToCostCentersPartitionKey(),
		Id:           c.UUID,
	}

	return &copy
}

func ToResourceLookUpKey(customerId string, resource *Resource) *Key {
	customer := NewCustomer(customerId)
	return toResourceLookUpKey(customer.ToCostCentersPartitionKey(), resource)
}

func toResourceLookUpKey(customerPartitionKey string, resource *Resource) *Key {
	return &Key{
		PartitionKey: customerPartitionKey,
		Id:           fmt.Sprintf("%s:%s:%s", DocumentIdResourceLookup, resource.Type, resource.Id),
	}
}

func resourceLookUpId(resource *Resource) string {
	return fmt.Sprintf("%s:%s:%s", DocumentIdResourceLookup, resource.Type, resource.Id)
}

func (c *CostCenterKey) AsResourceLookup(resource *Resource) *CostCenterKey {
	copy := *c
	copy.Key = &Key{PartitionKey: c.PartitionKey, Id: resourceLookUpId(resource)}
	copy.Customer = NewCustomerFromCostCenter(c)

	return &copy
}

func NewCostCenterKey(input *proto.CostCenterKey, createUUID bool) *CostCenterKey {
	customer := NewCustomer(input.CustomerId)

	u := input.Uuid
	if createUUID && u == "" {
		u = uuid.New().String()
	}

	key := &Key{
		PartitionKey: customer.ToCostCentersPartitionKey(),
		// i don't know if this will actually be the unique key for a cost cetner, or if multiple cost cetners can have the same target type and target id
		// can point to the same payment method
		// the alternative it to use uuid and make a entirely synthetic key. skipping for now for simplicty sake
		// in fact this might be sensitive data we should 100% not be sending to the UI as a parm value or whatever
		// TODO: figure out what the key should be
		// Id: fmt.Sprintf("%s:%s:%s", customer.ToPartitionKey(), input.TargetType, input.TargetId),
		Id: u,
	}
	return &CostCenterKey{
		Key:        key,
		Customer:   customer,
		TargetType: ToCostCenterType(input.TargetType),
		TargetId:   input.TargetId,
		UUID:       u,
	}
}

func NewCostCenterState(input proto.CostCenterState) CostCenterState {
	return CostCenterState(input)
}

func NewCostCenter(input *proto.CostCenter, createUUID bool) *CostCenter {
	resources := make([]*Resource, len(input.Resources))
	for i, r := range input.Resources {
		resources[i] = NewResource(r)
	}

	costCenterKey := NewCostCenterKey(input.CostCenterKey, createUUID)
	costCenterState := NewCostCenterState(input.CostCenterState)

	return &CostCenter{
		CostCenterKey:   costCenterKey,
		Name:            input.Name,
		Resources:       resources,
		CostCenterState: costCenterState,
	}
}

func (c *CostCenter) Validate(existingCostCenters []*CostCenter) error {
	for _, existingCostCenter := range existingCostCenters {
		if c.CostCenterKey.UUID != existingCostCenter.CostCenterKey.UUID {
			err := c.validateNameUniqueness(existingCostCenter)
			if err != nil {
				return err
			}

			err = c.validateResourceUniqueness(existingCostCenter)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

func (c *CostCenter) validateNameUniqueness(existingCostCenter *CostCenter) error {
	if c.Name == existingCostCenter.Name {
		return errors.Wrap(ErrorCostCenterConflict, "a cost center with that name already exists")
	}

	return nil
}

// Validate that the resources are unique by using maps to check for overlap
func (c *CostCenter) validateResourceUniqueness(existingCostCenter *CostCenter) error {
	newResourcesMap := c.getResourceMap()
	existingResourcesMap := existingCostCenter.getResourceMap()

	for resourceType := range newResourcesMap {
		for resourceId := range newResourcesMap[resourceType] {
			if _, isDuplicate := existingResourcesMap[resourceType][resourceId]; isDuplicate {
				return errors.Wrapf(ErrorCostCenterConflict, "one or more selected resources are already in use by cost center %s", existingCostCenter.Name)
			}
		}
	}

	return nil
}

func (c *CostCenter) getResourceMap() map[ResourceType]map[string]bool {
	if c.resourcesMap != nil {
		return c.resourcesMap
	}

	c.resourcesMap = make(map[ResourceType]map[string]bool)
	for _, resource := range c.Resources {
		if c.resourcesMap[resource.Type] == nil {
			c.resourcesMap[resource.Type] = make(map[string]bool)
		}
		c.resourcesMap[resource.Type][resource.Id] = true
	}
	return c.resourcesMap
}
