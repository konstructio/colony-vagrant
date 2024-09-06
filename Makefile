PWD := $(shell pwd)

.PHONY: dc
dc:
	@bash $(PWD)/virtual-datacenter/start.sh
