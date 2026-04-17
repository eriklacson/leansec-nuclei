FROM projectdiscovery/nuclei:latest

# Install cloud CLIs (extend for additional providers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg apt-transport-https ca-certificates && \
    echo "deb https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | apt-key add - && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /opt/nuclei/entrypoint.sh
COPY ../scanner/profiles/ /opt/nuclei/profiles/
RUN chmod +x /opt/nuclei/entrypoint.sh

ENTRYPOINT ["/opt/nuclei/entrypoint.sh"]
