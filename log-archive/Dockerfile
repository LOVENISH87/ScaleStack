# Log archive worker.
#
# Needs three things the stock CLI images do not all have: bash, tar/gzip (the
# S3 notification fires on logs/*.tar.gz, so the upload must be a real tarball)
# and the AWS CLI itself.
#
# Base choice matters: public.ecr.aws/aws-cli/aws-cli:2.x is Amazon Linux 2,
# which left support on 2025-06-30. Amazon Linux 2023 is supported and ships
# AWS CLI v2 in its own repositories, so the image gets a maintained base and a
# reproducible toolset with no curl-pipe-bash installer.
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# AL2023 ships a lean base: findutils and hostname are NOT present, and the
# archiver needs find. Install them explicitly instead of assuming.
RUN dnf install -y awscli tar gzip findutils hostname \
 && dnf clean all \
 && rm -rf /var/cache/dnf

COPY archive_pod_logs.sh /usr/local/bin/archive_pod_logs.sh
RUN chmod 0755 /usr/local/bin/archive_pod_logs.sh

CMD ["/usr/local/bin/archive_pod_logs.sh"]
