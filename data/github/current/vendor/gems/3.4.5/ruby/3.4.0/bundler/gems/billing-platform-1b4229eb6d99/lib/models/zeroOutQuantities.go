package models

type ZeroOutQuantitiesJobRun struct {
	CustomerId string
	Sku        string
	Year       string
	Month      string
}

type ZeroOutQuantitiesJob struct {
	JobRun *ZeroOutQuantitiesJobRun
}
