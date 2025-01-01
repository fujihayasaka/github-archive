package mocks

import _ "github.com/golang/mock/mockgen/model" // necessary for embedded interface imports https://github.com/golang/mock#debugging-errors

// Just a place for go:generate calls to generate mocks in a central place

//go:generate mockgen -destination ./publisher.go -source ../common/publisher/publisher.go -package mocks Publisher
//go:generate mockgen -destination ./notifications.go -package mocks github.com/github/authnd/internal/common/publisher NotificationPublisher
//go:generate mockgen -destination ./prat_event.go -package mocks github.com/github/authnd/internal/common/publisher PratEventPublisher
//go:generate mockgen -destination ./hedging.go -source ../common/hedging.go -package mocks HedgeManager

//go:generate mockgen -destination ./stats_client.go -package mocks -mock_names Client=StatsClient github.com/github/go-stats Client

//go:generate mockgen -destination ./sarama_consumer_group.go -package mocks github.com/IBM/sarama ConsumerGroup
//go:generate mockgen -destination ./sarama_consumer_group_handler.go -package mocks github.com/IBM/sarama ConsumerGroupHandler
//go:generate mockgen -destination ./sarama_consumer_group_claim.go -package mocks github.com/IBM/sarama ConsumerGroupClaim
//go:generate mockgen -destination ./sarama_consumer_group_session.go -package mocks github.com/IBM/sarama ConsumerGroupSession
