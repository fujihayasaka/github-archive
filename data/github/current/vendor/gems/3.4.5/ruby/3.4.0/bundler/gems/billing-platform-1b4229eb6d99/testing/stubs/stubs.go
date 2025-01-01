package stubs

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strconv"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	hydroSchemaRepos "github.com/github/billing-platform/generated/hydro/schemas/github/repositories/v1"
	hydroSchemaReposV2 "github.com/github/billing-platform/generated/hydro/schemas/github/repositories/v2"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	protobuf "google.golang.org/protobuf/proto"
)

func GetRandomId() int {
	return GetRandomIdMax(1000000)
}

func GetRandomId64() int64 {
	return int64(GetRandomIdMax(1000000))
}

func GetRandomId64AsString() string {
	return fmt.Sprintf("%d", GetRandomId64())
}

func GetRandomIdMax(max int64) int {
	rand, _ := rand.Int(rand.Reader, big.NewInt(max))
	return int(rand.Int64())
}

func GetRandomZuoraAccountNumber() string {
	return "A" + GetRandomId64AsString()
}

func CreateBudgetKey(customerId string, targetType proto.ResourceType, targetId string) *proto.BudgetKey {
	return CreateBudgetKeyWithPricing(customerId, targetType, targetId, proto.PricingTargetType_NoPricingTarget, "")
}
func CreateBudgetKeyWithPricing(customerId string, targetType proto.ResourceType, targetId string, pricingTargetType proto.PricingTargetType, pricingTargetId string) *proto.BudgetKey {
	return &proto.BudgetKey{
		CustomerId:        customerId,
		TargetType:        targetType,
		TargetId:          targetId,
		PricingTargetType: pricingTargetType,
		PricingTargetId:   pricingTargetId,
	}
}
func CreateBudgetWithPricing(customerId string, targetType proto.ResourceType, targetId string, pricingTargetType proto.PricingTargetType, pricingTargetId string, targetAmount float64) *proto.Budget {
	return CreateBudgetWithLimitType(customerId, targetType, targetId, pricingTargetType, pricingTargetId, targetAmount, proto.BudgetLimitType_IgnoreLimit)
}

func CreateBudgetWithLimitType(customerId string, targetType proto.ResourceType, targetId string, pricingTargetType proto.PricingTargetType, pricingTargetId string, targetAmount float64, budgetLimitType proto.BudgetLimitType) *proto.Budget {
	budgetAlerting := CreateBudgetAlerting([]string{customerId})
	return CreateBudgetWithAlerting(customerId, targetType, targetId, pricingTargetType, pricingTargetId, targetAmount, budgetLimitType, budgetAlerting)
}

func CreateBudgetWithAlerting(customerId string, targetType proto.ResourceType, targetId string, pricingTargetType proto.PricingTargetType, pricingTargetId string, targetAmount float64, budgetLimitType proto.BudgetLimitType, budgetAlerting *proto.BudgetAlerting) *proto.Budget {
	return &proto.Budget{
		Key:             CreateBudgetKeyWithPricing(customerId, targetType, targetId, pricingTargetType, pricingTargetId),
		TargetAmount:    targetAmount,
		BudgetLimitType: budgetLimitType,
		BudgetAlerting:  budgetAlerting,
	}
}

func CreateBudgetAlerting(userIDs []string) *proto.BudgetAlerting {
	return &proto.BudgetAlerting{
		WillAlert:        true,
		RecipientUserIds: userIDs,
	}
}

// Deprecated: use CreateBudgetWithPricing instead.
func CreateBudgetForNumeric(customerID int64, targetType proto.ResourceType, targetID int64, targetAmount float64) *proto.Budget {
	id := fmt.Sprintf("%d", targetID)
	cID := fmt.Sprintf("%d", customerID)
	return CreateBudgetWithPricing(cID, targetType, id, proto.PricingTargetType_NoPricingTarget, "", targetAmount)
}

// Deprecated: use CreateBudgetWithPricing instead.
func CreateBudget(customerId string, targetType proto.ResourceType, targetId string, targetAmount float64) *proto.Budget {
	return CreateBudgetWithPricing(customerId, targetType, targetId, proto.PricingTargetType_NoPricingTarget, "", targetAmount)
}

func CreateUsageWithEntity(usageUUID string, sku string, quantity float64, time time.Time, entity *hydroSchemaEntities.EntityDetail) *hydroSchema.Usage {
	params := &CreateUsageParams{
		UUID:           usageUUID,
		SKU:            sku,
		UsageAt:        time,
		Quantity:       quantity,
		CustomerId:     strconv.Itoa(int(entity.CustomerId)),
		OrganizationId: entity.OrganizationId,
		RepoId:         entity.RepoId,
		ActorId:        entity.ActorId,
	}
	usage, err := params.ToUsage()
	if err != nil {
		panic(err)
	}
	return usage
}

func CreateUsageFrom(pricing *proto.Pricing, entity *proto.EntityDetail, time time.Time, quantity float64) *hydroSchema.Usage {
	params := &CreateUsageParams{
		SKU:            pricing.GetSku(),
		UsageAt:        time,
		Quantity:       quantity,
		CustomerId:     entity.CustomerId,
		OrganizationId: entity.OwnerId,
		RepoId:         entity.RepoId,
		ActorId:        entity.ActorId,
	}
	usage, err := params.ToUsage()
	if err != nil {
		panic(err)
	}
	return usage
}

type CreateUsageParams struct {
	UUID      string
	SKU       string
	UsageAt   time.Time
	Quantity  float64
	SourceURI string

	CustomerId     string
	OrganizationId int64
	RepoId         int64
	ActorId        int64
}

func (p *CreateUsageParams) GetUUID() string {
	if p.UUID != "" {
		return p.UUID
	}

	return uuid.NewString()
}

func (p *CreateUsageParams) GetSourceUri() string {
	if p.SourceURI != "" {
		return p.SourceURI
	}

	return "git://run/id"
}

func (p *CreateUsageParams) GetCustomerId() (int64, error) {
	if p.CustomerId == "random" {
		p.CustomerId = GetRandomId64AsString()
	} else if p.CustomerId == "" {
		p.CustomerId = "0"
	}

	result, err := strconv.ParseInt(p.CustomerId, 10, 64)
	if err != nil {
		return -1, fmt.Errorf("failed to parse the customer id: %v", err)
	}
	return result, nil
}

func (p *CreateUsageParams) ToUsage() (*hydroSchema.Usage, error) {
	customerId, err := p.GetCustomerId()
	if err != nil {
		return nil, err
	}

	return &hydroSchema.Usage{
		UsageUuid: p.GetUUID(),
		Sku:       p.SKU,
		UsageAt:   timestamppb.New(p.UsageAt),
		Quantity:  p.Quantity,
		SourceUri: p.GetSourceUri(),
		Entity: &hydroSchemaEntities.EntityDetail{
			CustomerId:     customerId,
			OrganizationId: p.OrganizationId,
			RepoId:         p.RepoId,
			ActorId:        p.ActorId,
		},
	}, nil
}

func CreateUsage(usageUUID string, sku string, quantity float64, customerId string, time time.Time) *hydroSchema.Usage {
	params := &CreateUsageParams{
		UUID:           usageUUID,
		SKU:            sku,
		UsageAt:        time,
		Quantity:       quantity,
		CustomerId:     customerId,
		OrganizationId: GetRandomId64(),
		RepoId:         GetRandomId64(),
		ActorId:        GetRandomId64(),
	}
	usage, err := params.ToUsage()
	if err != nil {
		panic(err)
	}

	return usage
}

// TODO: this is a temporary function that can be removed after we've zeroed out backfill amounts
func CreateBackfillUsage(usageUUID string, sku string, quantity float64, customerId string, time time.Time) *hydroSchema.Usage {
	id, _ := strconv.ParseInt(customerId, 10, 64)
	entity := hydroSchemaEntities.EntityDetail{
		CustomerId:     id,
		OrganizationId: GetRandomId64(),
		RepoId:         GetRandomId64(),
		ActorId:        GetRandomId64(),
	}

	return &hydroSchema.Usage{
		UsageUuid: usageUUID,
		Sku:       sku,
		UsageAt:   timestamppb.New(time),
		Quantity:  quantity,
		SourceUri: "git://run/backfill",
		Entity:    &entity,
	}
}

func CreateUsageWithOrgRepo(sku string, quantity float64, customerId string, time time.Time, repoId, orgId int64) *hydroSchema.Usage {
	params := &CreateUsageParams{
		UUID:           uuid.NewString(),
		SKU:            sku,
		UsageAt:        time,
		Quantity:       quantity,
		CustomerId:     customerId,
		OrganizationId: orgId,
		RepoId:         repoId,
		ActorId:        GetRandomId64(),
	}
	usage, err := params.ToUsage()
	if err != nil {
		panic(err)
	}
	return usage
}

func CreateDollarDiscount(customerId string, targets []*proto.DiscountTarget, targetAmount float64, startDate, endDate int64) *proto.Discount {
	return &proto.Discount{
		CustomerId:   customerId,
		Targets:      targets,
		TargetAmount: targetAmount,
		StartDate:    startDate,
		EndDate:      endDate,
	}
}

func DollarDiscountForSku(customerID string, sku string, discountAmount float64, startDate, endDate int64) *proto.Discount {
	return CreateDollarDiscount(
		customerID,
		[]*proto.DiscountTarget{
			{
				Id:   sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		discountAmount,
		startDate,
		endDate,
	)
}

func CreatePercentageDiscount(customerId string, targets []*proto.DiscountTarget, percentage float64, startDate, endDate int64) *proto.Discount {
	return &proto.Discount{
		CustomerId: customerId,
		Targets:    targets,
		Percentage: percentage,
		StartDate:  startDate,
		EndDate:    endDate,
	}
}

func CreatePercentageDiscountForSku(customerId string, sku string, percentage float64) *proto.Discount {
	yesterday := time.Now().AddDate(0, 0, -1).Unix()
	nextYear := time.Now().AddDate(1, 0, 0).Unix()

	return &proto.Discount{
		CustomerId: customerId,
		Targets: []*proto.DiscountTarget{
			{
				Id:   sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		Percentage: percentage,
		StartDate:  yesterday,
		EndDate:    nextYear,
	}
}

func PercentageDiscountForSkuWithDates(customerID string, sku string, percentage float64, startDate, endDate int64) *proto.Discount {
	return &proto.Discount{
		CustomerId: customerID,
		Targets: []*proto.DiscountTarget{
			{
				Id:   sku,
				Type: proto.DiscountTargetType_SkuDiscount,
			},
		},
		Percentage: percentage,
		StartDate:  startDate,
		EndDate:    endDate,
	}
}

func GetResource(entity *proto.EntityDetail, resourceType proto.ResourceType) *proto.Resource {
	return &proto.Resource{
		Type: resourceType,
		Id:   GetResourceIDFromEntityByType(entity, resourceType),
	}
}

func CreateResources(resources map[int64]proto.ResourceType) []*proto.Resource { // move this to costcenter stubs
	var result []*proto.Resource
	for id, resourceType := range resources {
		result = append(result, &proto.Resource{Type: resourceType, Id: strconv.Itoa(int(id))})
	}
	return result
}

func GetResourceIDFromEntityByType(entity *proto.EntityDetail, resourceType proto.ResourceType) string {
	var id int64
	switch resourceType {
	case proto.ResourceType_Repo:
		id = entity.RepoId
	case proto.ResourceType_Org:
		id = entity.OwnerId
	case proto.ResourceType_Enterprise:
		return entity.CustomerId
	case proto.ResourceType_User:
		id = entity.ActorId
	}
	return fmt.Sprintf("%d", id)
}

func CreateEntity() *proto.EntityDetail {
	customerID := GetRandomId64AsString()
	ownerID := GetRandomId64()
	repoID := GetRandomId64()
	actorID := GetRandomId64()
	return &proto.EntityDetail{
		CustomerId: customerID,
		OwnerId:    ownerID,
		RepoId:     repoID,
		ActorId:    actorID,
	}

}

func CreateEntityAll(customerID string, ownerID int64, repoID int64, actorID int64) *proto.EntityDetail {

	return &proto.EntityDetail{
		CustomerId: customerID,
		OwnerId:    ownerID,
		RepoId:     repoID,
		ActorId:    actorID,
	}

}

func SetupZuoraServer(mockResponses []func(rw http.ResponseWriter, r *http.Request)) *httptest.Server {
	counter := 0
	mockServer := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		if req.RequestURI == "/oauth/token" {
			// mock get token response
			_, _ = rw.Write([]byte("access_token=mocktoken&scope=user&token_type=bearer&expires_in=3600&jti=abc"))
		} else if counter < len(mockResponses) {
			mockResponses[counter](rw, req)
			counter++
		}
	}))

	return mockServer
}

func NewRepoVisibilityChangedMessage(repoId int64, isPublic bool) *hydroSchemaRepos.VisibilityChanged {
	var oldVisibility, newVisibility hydroSchemaRepos.VisibilityChanged_Visibility
	if isPublic {
		oldVisibility = hydroSchemaRepos.VisibilityChanged_PRIVATE
		newVisibility = hydroSchemaRepos.VisibilityChanged_PUBLIC
	} else {
		oldVisibility = hydroSchemaRepos.VisibilityChanged_PUBLIC
		newVisibility = hydroSchemaRepos.VisibilityChanged_PRIVATE
	}

	return &hydroSchemaRepos.VisibilityChanged{
		RepositoryId:  repoId,
		ActorId:       GetRandomId64(),
		RequestId:     GetRandomId64AsString(),
		OldVisibility: oldVisibility,
		NewVisibility: newVisibility,
	}
}

func NewRepositoryRestoredMessage(repoId int64) *hydroSchemaReposV2.Restored {
	return &hydroSchemaReposV2.Restored{
		RepositoryId: repoId,
		ActorId:      GetRandomId64(),
		RequestId:    GetRandomId64AsString(),
		DeletedAt:    &timestamppb.Timestamp{Seconds: 12344515321},
	}
}

func CreateEnvelope(message []byte) *schemas.Envelope {
	eventCreatedAt := int64(12344515321)
	return &schemas.Envelope{
		Message:   message,
		Timestamp: &timestamppb.Timestamp{Seconds: eventCreatedAt},
	}
}

func CreateEnvelopeForVisibilityChangedEvent(repoId int64, isPublic bool) (*schemas.Envelope, error) {
	message := NewRepoVisibilityChangedMessage(repoId, isPublic)
	encodedMessage, err := protobuf.Marshal(message)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal message")
	}

	return CreateEnvelope(encodedMessage), nil
}

func CreateEnvelopeForRepositoryRestoredEvent(repoId int64) (*schemas.Envelope, error) {
	message := NewRepositoryRestoredMessage(repoId)
	encodedMessage, err := protobuf.Marshal(message)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal message")
	}

	return CreateEnvelope(encodedMessage), nil
}
