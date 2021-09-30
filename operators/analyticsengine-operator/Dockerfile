ARG ARCH=amd64
FROM cp.stg.icr.io/cp/ibm-cpd-analyticsengine-operator:1.0.245-${ARCH} AS builder

FROM quay.io/operator-framework/ansible-operator:v1.4.2
LABEL ANALYTICSENGINE_BUILD=BUILD_NUMBER

USER root

RUN yum update -y && \
    pip3 uninstall -y ansible && \
    pip3 install ansible==2.10.5 && \
    mkdir -p ${HOME}/roles/4.0.0 && \
    mkdir -p ${HOME}/roles/4.0.1 && \
    mkdir -p ${HOME}/vars/4.0.0 && \
    mkdir -p ${HOME}/vars/4.0.1

COPY --from=builder ${HOME}/roles ${HOME}/roles/4.0.0/
COPY --from=builder ${HOME}/playbooks/vars/digests.yaml ${HOME}/vars/4.0.0/digests.yaml
COPY --from=builder ${HOME}/playbooks/vars/scale-config ${HOME}/vars/4.0.0/scale-config

USER 1001

COPY LICENSE /licenses/
COPY requirements.yml ${HOME}/requirements.yml
RUN  ansible-galaxy collection install -r ${HOME}/requirements.yml && \
     chmod -R ug+rwx ${HOME}/.ansible

COPY watches.yaml ${HOME}/watches.yaml
COPY roles/ ${HOME}/roles/4.0.1/
COPY playbooks/install.yml ${HOME}/install.yml
COPY playbooks/vars/digests.yaml ${HOME}/vars/4.0.1/digests.yaml
COPY playbooks/vars/scale-config ${HOME}/vars/4.0.1/scale-config

USER root

RUN cp -a ${HOME}/roles/4.0.1/common/tasks/set_scale_size.yaml ${HOME}/roles/4.0.0/common/tasks/set_scale_size.yaml

USER 1001