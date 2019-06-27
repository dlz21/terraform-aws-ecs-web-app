import os
import json, boto3

def lambda_handler(event, context):
    region = os.environ['ELB_REGION']
    elbv2_client = boto3.client('elbv2', region_name=region)

    available_target_groups = os.environ['AVAILABLE_TARGET_GROUPS']
    arrMatches = available_target_groups.split(',')

    # Get HTTP Target Group.
    http_listener_arn = os.environ['HTTP_LISTENER_ARN']
    http_listener = elbv2_client.describe_rules( ListenerArn=http_listener_arn)
    http_target_group_arn = get_current_http_target_group(http_listener['Rules'], arrMatches)

    if http_target_group_arn==False:
        print("Could not identify the target arn")
        return False

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

        rule_modded = 0
        n = 0
        while n < len(actions):
            if actions[n]['TargetGroupArn'] in arrMatches:
                actions[n]['TargetGroupArn']=http_target_group_arn
                rule_modded=1

            n +=1

        if rule_modded==1:
            results[https_listener_rules[i]['RuleArn']] = elbv2_client.modify_rule(
                RuleArn=https_listener_rules[i]['RuleArn'],
                Actions=actions
            )

        i +=1

    return results

# Returns the current B/G target group from a list of lister rules.
def get_current_http_target_group(http_listener_rules, arrMatches):

    i=0
    while i < len(http_listener_rules):

        # Continue if default listener rule.
        if http_listener_rules[i]['IsDefault']==True:
            i +=1
            continue

        actions = http_listener_rules[i]['Actions']
        n=0
        while n<len(actions):
            if actions[n]['TargetGroupArn'] in arrMatches:
                return actions[n]['TargetGroupArn']

            n +=1

        i +=1

    return False;
