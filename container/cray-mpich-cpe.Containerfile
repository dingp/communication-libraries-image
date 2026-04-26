# Example HPE Cray MPICH image recipe.
#
# HPE Cray MPICH is not distributed from a public source tarball. This recipe
# expects access to an HPE CPE package repository or a site-local mirror.

ARG SLES_IMAGE=registry.suse.com/suse/sles15sp5:latest
FROM ${SLES_IMAGE} AS cray-mpich-cpe

ARG HPE_CPE_REPO_URL
ARG HPE_CPE_GPG_KEY_URL
ARG CRAY_MPICH_PACKAGE=cray-mpich-9.0.1-gnu123
ARG CRAY_GTL_PACKAGE=cray-mpich-9.0.1-gtl
ARG CRAY_PMI_PACKAGE=cray-pmi
ARG CRAY_PALS_PACKAGE=cray-pals
ARG CRAYPE_PACKAGE=craype

RUN test -n "${HPE_CPE_REPO_URL}" \
    && zypper --non-interactive install ca-certificates curl gzip tar \
    && if test -n "${HPE_CPE_GPG_KEY_URL}"; then rpm --import "${HPE_CPE_GPG_KEY_URL}"; fi \
    && zypper addrepo -f "${HPE_CPE_REPO_URL}" cpe \
    && zypper --non-interactive refresh \
    && zypper --non-interactive install \
       ${CRAYPE_PACKAGE} \
       ${CRAY_PALS_PACKAGE} \
       ${CRAY_PMI_PACKAGE} \
       ${CRAY_MPICH_PACKAGE} \
       ${CRAY_GTL_PACKAGE} \
    && zypper removerepo cpe

ENV CRAY_MPICH_PREFIX=/opt/cray/pe/mpich/9.0.1/ofi/gnu/12.3
ENV MPICH_DIR=/opt/cray/pe/mpich/9.0.1/ofi/gnu/12.3
ENV PATH=/opt/cray/pe/mpich/9.0.1/bin:/opt/cray/pe/mpich/9.0.1/ofi/gnu/12.3/bin:${PATH}
ENV LD_LIBRARY_PATH=/opt/cray/pe/mpich/9.0.1/ofi/gnu/12.3/lib:/opt/cray/pe/mpich/9.0.1/gtl/lib:/opt/cray/pe/pmi/default/lib:${LD_LIBRARY_PATH}
ENV PKG_CONFIG_PATH=/opt/cray/pe/mpich/9.0.1/ofi/gnu/12.3/lib/pkgconfig:${PKG_CONFIG_PATH}
ENV FI_PROVIDER=cxi
ENV PMIX_MCA_psec=native

