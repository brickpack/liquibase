import boto3
import json
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda function to automatically stop RDS databases to reduce costs.
    Designed to run on a schedule to keep databases shut down when not in use.
    """

    rds_client = boto3.client('rds')

    stopped_instances = []
    errors = []

    try:
        # Get all RDS instances
        response = rds_client.describe_db_instances()

        for db_instance in response['DBInstances']:
            db_identifier = db_instance['DBInstanceIdentifier']
            db_status = db_instance['DBInstanceStatus']
            engine = db_instance['Engine']

            logger.info(f"Processing database: {db_identifier} (Status: {db_status}, Engine: {engine})")

            # Only attempt to stop databases that are currently available
            if db_status == 'available':
                try:
                    # Check if this is a database we should manage
                    # Skip production databases or databases with specific tags
                    if should_stop_database(rds_client, db_identifier):
                        logger.info(f"Stopping database: {db_identifier}")

                        rds_client.stop_db_instance(
                            DBInstanceIdentifier=db_identifier
                        )

                        stopped_instances.append({
                            'identifier': db_identifier,
                            'engine': engine,
                            'status': 'stop_initiated'
                        })

                    else:
                        logger.info(f"Skipping database {db_identifier} - marked as persistent or production")

                except Exception as e:
                    error_msg = f"Failed to stop {db_identifier}: {str(e)}"
                    logger.error(error_msg)
                    errors.append(error_msg)

            elif db_status in ['stopped', 'stopping']:
                logger.info(f"Database {db_identifier} is already stopped or stopping")

            else:
                logger.info(f"Database {db_identifier} is in {db_status} state - skipping")

    except Exception as e:
        error_msg = f"Failed to list RDS instances: {str(e)}"
        logger.error(error_msg)
        errors.append(error_msg)

    # Return summary
    result = {
        'statusCode': 200,
        'body': {
            'stopped_instances': stopped_instances,
            'total_stopped': len(stopped_instances),
            'errors': errors,
            'timestamp': context.aws_request_id
        }
    }

    logger.info(f"Lambda execution completed. Stopped {len(stopped_instances)} databases.")
    return result

def should_stop_database(rds_client: boto3.client, db_identifier: str) -> bool:
    """
    Determine if a database should be automatically stopped.
    Returns False for production databases or databases tagged as persistent.
    """
    try:
        # Get database tags
        response = rds_client.list_tags_for_resource(
            ResourceName=f"arn:aws:rds:*:*:db:{db_identifier}"
        )

        tags = {tag['Key']: tag['Value'] for tag in response.get('TagList', [])}

        # Skip databases with these tags
        if tags.get('Environment', '').lower() == 'production':
            return False

        if tags.get('AutoStop', '').lower() == 'false':
            return False

        if tags.get('Persistent', '').lower() == 'true':
            return False

        # Skip databases with 'prod' in the name
        if 'prod' in db_identifier.lower():
            return False

        # Default to allowing stop for dev/test databases
        return True

    except Exception as e:
        logger.error(f"Failed to check tags for {db_identifier}: {str(e)}")
        # If we can't check tags, err on the side of caution
        return False