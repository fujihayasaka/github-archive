package concurrency

// NewLimiter creates a limiter that can be used to limit the number of goroutines spawned.
// Use Check() before spawning a goroutine and defer l.Done() inside each goroutine.
func NewLimiter(max int) *Limiter {
	if max <= 0 {
		panic("Max must be positive")
	}
	return &Limiter{ch: make(chan struct{}, max)}
}

type Limiter struct {
	ch chan struct{}
}

// Check blocks a go routine until the number of outstanding bits of work is low enough
func (l *Limiter) Check() {
	l.ch <- struct{}{}
}

// Done decrements the number of waiting items
func (l *Limiter) Done() {
	<-l.ch
}
