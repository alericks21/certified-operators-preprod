# copied from https://github.ibm.com/CloudPakOpenContent/operator-build-scripts/blob/65a6cb9cad775a03cd2772da83287b1cfde892a4/buildIndex.sh#L50-L60
FROM registry.redhat.io/openshift4/ose-operator-registry:v4.6 AS builder
FROM registry.access.redhat.com/ubi8/ubi-minimal
LABEL ANALYTICSENGINE_BUILD=BUILD_NUMBER
LABEL operators.operatorframework.io.index.database.v1=/database/index.db

USER root
RUN microdnf update -y && \
	mkdir -p /home/catalog && \
    chown 1001:root /home/catalog
    
USER 1001

COPY --chown=1001:root LICENSE /licenses/
COPY --chown=1001:root bundles.db /database/index.db
COPY --from=builder --chown=1001:root /bin/opm /bin/opm
COPY --from=builder --chown=1001:root /bin/grpc_health_probe /bin/grpc_health_probe

WORKDIR /home/catalog

EXPOSE 50051
ENTRYPOINT ["/bin/opm"]
CMD ["registry", "serve", "--database", "/database/index.db","-t","/tmp/termination-log"]