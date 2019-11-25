import json
import logging
import os
import pandas
import requests

from datetime import datetime

from azure.kusto.data.request import KustoConnectionStringBuilder
from azure.kusto.ingest import (
    KustoIngestClient,
    IngestionProperties,
    BlobDescriptor,
    DataFormat
)

import azure.functions as func

DATA_TABLE = 'OsVersion'
DATA_URL = 'os_version'
#DATA_MAPPING = 'AppsMapping'

def get_kusto_client() -> KustoIngestClient:
    cluster = "https://ingest-" + os.environ['KUSTO_CLUSTER'] + ".kusto.windows.net"
    username = os.environ['KUSTO_USERNAME']
    password = os.environ['KUSTO_PASSWORD']
    authority_id = os.environ['KUSTO_TENANT_ID']

    kcsb = KustoConnectionStringBuilder.with_aad_user_password_authentication(cluster, username, password, authority_id)

    return KustoIngestClient(kcsb)


def main(timer: func.TimerRequest, outputBlob: func.Out[str]) -> None:

    now = datetime.utcnow().isoformat(timespec='milliseconds') + 'Z'
    data = []

    limit = 100
    skip = 0
    records = 100

    url = 'https://console.jumpcloud.com/api/v2/systeminsights/' + DATA_URL
    headers = {'Content-Type': 'application/json', 'x-api-key': os.environ['JUMPCLOUD_API_KEY']}

    while not records < limit:
        logging.info(f'Requesting {limit} records starting at {skip}')
        
        payload = { 'limit': limit, 'skip' : skip }
        obj = requests.get(url, params = payload, headers = headers).json()

        records = len(obj)
        logging.info(f'Received {records} records')

        for i in range(records):
           obj[i]['batch_time'] = now
           data.append(obj[i])

        skip += records

    kusto = get_kusto_client()
    ingestion_props = IngestionProperties(
        database=os.environ['KUSTO_DATABASE'],
        table=DATA_TABLE,
        dataFormat=DataFormat.CSV
        #ingestionMappingReference=DATA_MAPPING,
        #ingestionMappingType=IngestionMappingType.CSV
    )

    kusto.ingest_from_dataframe(pandas.DataFrame(data), ingestion_properties=ingestion_props)

    outputBlob.set(json.dumps(data))