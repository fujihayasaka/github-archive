package models

import (
	"fmt"
)

const (
	PartitionKeyActiveHourly  = "active:hourly"
	PartitionKeyActiveDaily   = "active:daily"
	PartitionKeyActiveMonthly = "active:monthly"
	PartitionKeyActiveYearly  = "active:yearly"
	PartitionKeyActiveEvent   = "active:%s:events"
)

type ActiveTypePart byte

const (
	H ActiveTypePart = 1 << iota
	D
	M
)

type ActiveType byte

const (
	Unknown ActiveType = 0 << iota
	Hourly  ActiveType = 1
	Daily   ActiveType = 3
	Monthly ActiveType = 7
	Yearly  ActiveType = 15
)

func (e ActiveType) String() string {
	switch e {
	case Hourly:
		return "Hourly"
	case Daily:
		return "Daily"
	case Monthly:
		return "Monthly"
	case Yearly:
		return "Yearly"
	default:
		return fmt.Sprintf("%d", int(e))
	}
}

func (activeType ActiveType) GetPartitionKeyTypeName() string {
	switch activeType {
	case Hourly:
		return PartitionKeyActiveHourly
	case Daily:
		return PartitionKeyActiveDaily
	case Monthly:
		return PartitionKeyActiveMonthly
	case Yearly:
		return PartitionKeyActiveYearly
	default:
		return fmt.Sprintf("%d", int(activeType))
	}
}

func (a ActiveType) Includes(t ActiveTypePart) bool {
	return byte(a)&byte(t) != 0
}
