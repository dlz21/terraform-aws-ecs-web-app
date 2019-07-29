import os
import json, boto3

def lambda_handler(event, context):
    print("Trigger Event: ")
    print(event)
    region = os.environ['REGION']
    elbv2_client = boto3.client('elbv2', region_name=region)

    available_target_groups = os.environ['AVAILABLE_TARGET_GROUPS']
    arr_available_target_groups = available_target_groups.split(',')

    # Get HTTP Target Group.
    http_listener_arn = os.environ['HTTP_LISTENER_ARN']
    http_listener = elbv2_client.describe_rules( ListenerArn=http_listener_arn)
    http_target_group_arn = get_current_http_target_group(http_listener['Rules'], arr_available_target_groups)

    if http_target_group_arn==False:
        print("Could not identify the target arn")
        return False

    print("Current HTTP target group: ")
    print(http_target_group_arn)

    # Get HTTPS listener rules.
    https_listener_arn = os.environ['SSL_LISTENER_ARN']
    https_listener = elbv2_client.describe_rules(ListenerArn=https_listener_arn)
    https_listener_rules = https_listener['Rules']

    results = {}
    i = 0
    while i < len(https_listener_rules):

        if https_listener_rules[i]['IsDefault']==True:
            i +=1
            continue

        actions = https_listener_rules[i]['Actions']

        modify_rule = 0
        n = 0
        while n < len(actions):
            try:
                target_is_updated = check_target_update(actions[n]['TargetGroupArn'], arr_available_target_groups, http_target_group_arn)

                if target_is_updated:
                    actions[n]['TargetGroupArn']=http_target_group_arn
                    modify_rule=1
            except Exception as e:
                pass

            n +=1

        if modify_rule==1:
            print("Updating SSL listener rules..")
            results[https_listener_rules[i]['RuleArn']] = elbv2_client.modify_rule(
                RuleArn=https_listener_rules[i]['RuleArn'],
                Actions=actions
            )

        i +=1

    # For ECS After Allow Test Traffic hook
    try:
        send_codedeploy_validation_status(event['DeploymentId'], event['LifecycleEventHookExecutionId'], results)
    except Exception as e:
        print('Recoverable Exception: ')
        print(e)

    print(results)
    return results

# Returns the current B/G target group from a list of lister rules.
def get_current_http_target_group(http_listener_rules, arr_available_target_groups):

    i=0
    while i < len(http_listener_rules):

        # Continue if default listener rule.
        if http_listener_rules[i]['IsDefault']==True:
            i +=1
            continue

        actions = http_listener_rules[i]['Actions']
        n=0
        while n<len(actions):

            try:
                if actions[n]['TargetGroupArn'] in arr_available_target_groups:
                    return actions[n]['TargetGroupArn']
            except Exception as e:
                pass

            n +=1

        i +=1

    return False


# Check old target group is associated w/out available target and different.
def check_target_update(old_target_group, arr_available_target_groups, new_target_group):

    return old_target_group in arr_available_target_groups and old_target_group != new_target_group


# Sends notification to CodeDeploy on hook status...
def send_codedeploy_validation_status(deployment_id, execution_id, results):
    region = os.environ['REGION']
    codedeploy_client = boto3.client('codedeploy', region_name=region)
    status = ('Failed', 'Succeeded')[len(results) > 0]

    print(status)

    return codedeploy_client.put_lifecycle_event_hook_execution_status(
        deploymentId=deployment_id,
        lifecycleEventHookExecutionId=execution_id,
        status=status
    )
