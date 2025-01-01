package mysql

import (
	"math/rand"
	"sync"
	"testing"
	"time"
)

func TestHedgeManager_NoRaceConditions(t *testing.T) {
	// experimentally tuned to reliably produce a race condition when present, but not take
	// too long (130ms) to run with the race detector enabled when no race condition exists.
	observations := 10_000
	writers := 2
	readers := 5

	hm := NewHedgeManager()
	done := make(chan struct{})

	var writeWG, readWG sync.WaitGroup
	writeWG.Add(writers)
	readWG.Add(readers)

	// workers adding observations
	for thread := 0; thread < writers; thread++ {
		go func() {
			defer writeWG.Done()
			for ix := 0; ix < observations/writers; ix++ {
				hm.HandleOperationDuration(time.Duration(100*rand.Float64()) * time.Millisecond)
			}
		}()
	}

	// workers observing wait times
	for thread := 0; thread < readers; thread++ {
		go func() {
			defer readWG.Done()

			for {
				select {
				case <-done:
					return
				case <-time.After(10_000 * time.Nanosecond):
					hm.GetWaitTime()
				}
			}
		}()
	}

	// close the done channel when all workers are done
	go func() {
		writeWG.Wait()
		close(done)
	}()

	// wait for all reads to be done
	readWG.Wait()
}
