package mu

import (
	"fmt"
	"sort"
)

type serviceInfo struct {
	Name    string         `json:"name"`
	Address string         `json:"address"`
	Methods serviceMethods `json:"methods"`
}

func (s serviceInfo) String() string {
	var str string
	if len(s.Address) > 0 {
		str = fmt.Sprintf("%s %s\n\n", s.Name, s.Address)
	} else {
		str = fmt.Sprintf("%s (no listener)\n\n", s.Name)
	}
	if len(s.Methods) == 0 {
		str += "\tNo routes\n"
	} else {
		sort.Sort(s.Methods)
		for _, m := range s.Methods {
			str += fmt.Sprintf("\t%s\n", m)
		}
	}
	return str
}

type serviceMethod struct {
	Name   string `json:"name"`
	Method string `json:"method,omitempty"`
	Route  string `json:"route,omitempty"`
}

func (m serviceMethod) String() string {
	str := ""
	if len(m.Method) > 0 {
		str += fmt.Sprintf("%-8s", m.Method)
	}
	if len(m.Route) > 0 {
		str += fmt.Sprintf("%-40s", m.Route)
	}
	return fmt.Sprintf("%s%s", str, m.Name)
}

type serviceMethods []serviceMethod

func (m serviceMethods) Len() int      { return len(m) }
func (m serviceMethods) Swap(i, j int) { m[i], m[j] = m[j], m[i] }
func (m serviceMethods) Less(i, j int) bool {
	if m[i].Route == m[j].Route {
		if m[i].Method == m[j].Method {
			return m[i].Name < m[j].Name
		}
		return m[i].Method < m[j].Method
	}
	return m[i].Route < m[j].Route
}
