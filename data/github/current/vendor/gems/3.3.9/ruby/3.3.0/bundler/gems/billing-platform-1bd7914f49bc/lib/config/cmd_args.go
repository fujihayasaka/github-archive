package config

import (
	"flag"
	"time"
)

type CommandArgs struct {
	RunLimited                       bool
	NumberOfLimitedMessagesToProcess int
	TimeTravel                       bool
	TimeTravelDate                   time.Time
	TestingCollectionName            string
	TestingQueueName                 string
	TestingDatabaseName              string
	ZuoraApiUrl                      string
	MonolithTwirpServerURL           string
}

const (
	ParameterNameRunLimited                       = "runLimited"
	ParameterNameNumberOfLimitedMessagesToProcess = "num"
	ParameterNameTimeTravel                       = "timeTravel"
	ParameterNameTimeTravelDate                   = "timeTravelDate"
	ParameterTimeTravelFormat                     = time.RFC3339
	ParameterNameTestingCollectionName            = "collectionName"
	ParameterNameTestingQueueName                 = "testingQueueName"
	ParameterNameTestingDatabaseName              = "testingDatabaseName"
	ParameterZuoraApiUrl                          = "zuoraApiURL"
	ParameterMonolithTwirpServerURL               = "monolithTwirpServerURL"
)

func getCommandLineFlags(cfg *Config) *CommandArgs {
	if cfg == nil {
		return nil
	}

	if cfg.IsProduction() {
		return &CommandArgs{}
	}

	runLimited := flag.Bool(ParameterNameRunLimited, false, "set if running locally for testing")
	numberOfLimitedMessagesToProcess := flag.Int("num", 0, "set to determine how may message to process")
	timeTravel := flag.Bool(ParameterNameTimeTravel, false, "set to time travel for testing ingestion")
	timeTravelUnix := flag.String(ParameterNameTimeTravelDate, time.Now().UTC().Format(ParameterTimeTravelFormat), "set to time travel for testing ingestion")
	testingCollectionName := flag.String(ParameterNameTestingCollectionName, "", "set to use custom collection name for testing")
	testingQueueName := flag.String(ParameterNameTestingQueueName, "", "set to use custom queue name for testing")
	testingDatabaseName := flag.String(ParameterNameTestingDatabaseName, "", "set to use custom database name for testing")
	zuoraApiUrl := flag.String(ParameterZuoraApiUrl, "", "set to use custom zuora api url for testing")
	monolithTwirpServerURL := flag.String(ParameterMonolithTwirpServerURL, "", "set to use custom monolith twirp server url for testing")

	flag.Parse()

	var timeTravelDate time.Time
	if *timeTravel {
		d, err := time.Parse(ParameterTimeTravelFormat, *timeTravelUnix)
		if err != nil {
			panic(err)
		}
		timeTravelDate = d
	}

	return &CommandArgs{
		RunLimited:                       *runLimited,
		NumberOfLimitedMessagesToProcess: *numberOfLimitedMessagesToProcess,
		TimeTravel:                       *timeTravel,
		TimeTravelDate:                   timeTravelDate,
		TestingCollectionName:            *testingCollectionName,
		TestingQueueName:                 *testingQueueName,
		TestingDatabaseName:              *testingDatabaseName,
		ZuoraApiUrl:                      *zuoraApiUrl,
		MonolithTwirpServerURL:           *monolithTwirpServerURL,
	}
}
