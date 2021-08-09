NAME=timescaledb
# Default is to timescaledev to avoid unexpected push to the main repo
# Set ORG to timescale in the caller
ORG=timescaledev
PG_VER=pg12
PG_VER_NUMBER=$(shell echo $(PG_VER) | cut -c3-)
TS_VERSION=master
PREV_TS_VERSION=$(shell wget --quiet -O - https://raw.githubusercontent.com/timescale/timescaledb/${TS_VERSION}/version.config | grep update_from_version | sed -e 's!update_from_version = !!')
# Beta releases should not be tagged as latest, so BETA is used to track.
BETA=$(findstring rc,$(TS_VERSION))
PLATFORM=linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64
NIGHTLY_PLATFORM=linux/amd64

# PUSH_MULTI can be set to nothing for dry-run without pushing during multi-arch build
PUSH_MULTI=--push
TAG_NIGHTLY=-t timescaledev/timescaledb:nightly-$(PG_VER)
TAG_VERSION=$(ORG)/$(NAME):$(TS_VERSION)-$(PG_VER)
TAG_LATEST=$(ORG)/$(NAME):latest-$(PG_VER)
TAG=-t $(TAG_VERSION) $(if $(BETA),,-t $(TAG_LATEST))
TAG_OSS=-t $(TAG_VERSION)-oss $(if $(BETA),,-t $(TAG_LATEST)-oss)

default: image

.multi_$(TS_VERSION)_$(PG_VER)_oss: Dockerfile
	test -n "$(TS_VERSION)"  # TS_VERSION
	test -n "$(PREV_TS_VERSION)"  # PREV_TS_VERSION
	docker buildx create --platform $(PLATFORM) --name multibuild --use
	docker buildx inspect multibuild --bootstrap
	docker buildx build --platform $(PLATFORM) \
		--build-arg TS_VERSION=$(TS_VERSION) \
		--build-arg PREV_TS_VERSION=$(PREV_TS_VERSION) \
		--build-arg PG_VERSION=$(PG_VER_NUMBER) \
		--build-arg PREV_EXTRA="-oss" \
		--build-arg OSS_ONLY=" -DAPACHE_ONLY=1" \
		$(TAG_OSS) $(PUSH_MULTI) .
	touch .multi_$(TS_VERSION)_$(PG_VER)_oss
	docker buildx rm multibuild

.multi_$(TS_VERSION)_$(PG_VER): Dockerfile
	test -n "$(TS_VERSION)"  # TS_VERSION
	test -n "$(PREV_TS_VERSION)"  # PREV_TS_VERSION
	docker buildx create --platform $(PLATFORM) --name multibuild --use
	docker buildx inspect multibuild --bootstrap
	docker buildx build --platform $(PLATFORM) \
		--build-arg TS_VERSION=$(TS_VERSION) \
		--build-arg PREV_TS_VERSION=$(PREV_TS_VERSION) \
		--build-arg PG_VERSION=$(PG_VER_NUMBER) \
		$(TAG) $(PUSH_MULTI) .
	touch .multi_$(TS_VERSION)_$(PG_VER)
	docker buildx rm multibuild

.nightly_$(PG_VER): Dockerfile
	test -n "$(TS_VERSION)"  # TS_VERSION
	test -n "$(PREV_TS_VERSION)"  # PREV_TS_VERSION
	docker buildx create --platform $(NIGHTLY_PLATFORM) --name nightlybuild --use
	docker buildx inspect nightlybuild --bootstrap
	docker buildx build --platform $(NIGHTLY_PLATFORM) \
		--build-arg TS_VERSION=$(TS_VERSION) \
		--build-arg PREV_TS_VERSION=$(PREV_TS_VERSION) \
		--build-arg PG_VERSION=$(PG_VER_NUMBER) \
		$(TAG_NIGHTLY) $(PUSH_MULTI) .
	touch .nightly_$(PG_VER)
	docker buildx rm nightlybuild

.build_$(TS_VERSION)_$(PG_VER)_oss: Dockerfile
	docker build --build-arg PREV_EXTRA="-oss" --build-arg OSS_ONLY=" -DAPACHE_ONLY=1" --build-arg PG_VERSION=$(PG_VER_NUMBER) $(TAG_OSS) .
	touch .build_$(TS_VERSION)_$(PG_VER)_oss

.build_$(TS_VERSION)_$(PG_VER): Dockerfile
	docker build --build-arg PG_VERSION=$(PG_VER_NUMBER) $(TAG) .
	touch .build_$(TS_VERSION)_$(PG_VER)

image: .build_$(TS_VERSION)_$(PG_VER)

oss: .build_$(TS_VERSION)_$(PG_VER)_oss

push: image
	docker push $(TAG_VERSION)
	if [ -z "$(BETA)" ]; then \
		docker push $(TAG_LATEST); \
	fi

push-oss: oss
	docker push $(TAG_VERSION)-oss
	if [ -z "$(BETA)" ]; then \
		docker push $(TAG_LATEST)-oss; \
	fi

multi: .multi_$(TS_VERSION)_$(PG_VER)

multi-oss: .multi_$(TS_VERSION)_$(PG_VER)_oss

nightly: .nightly_$(PG_VER)

all: multi multi-oss

clean:
	rm -f *~ .build_* .multi_* .nightly*
	-docker buildx rm nightlybuild
	-docker buildx rm multibuild

.PHONY: default image push push-oss oss multi multi-oss clean all
