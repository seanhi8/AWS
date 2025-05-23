DefinitionString:
  Fn::Sub: |
    {
      "StartAt": "StartStep1Async",
      "States": {
        "StartStep1Async": {
          "Type": "Task",
          "Resource": "arn:aws:states:::states:startExecution",
          "Parameters": {
            "StateMachineArn": "${Step1StateMachineArn}",
            "Input": {}
          },
          "Next": "InitPollingVars"
        },
        "InitPollingVars": {
          "Type": "Pass",
          "Result": {
            "count": 0,
            "streak": 0
          },
          "ResultPath": "$.vars",
          "Next": "CheckS3_001"
        },
        "CheckS3_001": {
          "Type": "Task",
          "Resource": "arn:aws:states:::lambda:invoke",
          "Parameters": {
            "FunctionName": "${CheckS3Lambda}",
            "Payload": {
              "bucket": "${Bucket001}"
            }
          },
          "ResultPath": "$.check",
          "Next": "EvaluateCheck"
        },
        "EvaluateCheck": {
          "Type": "Choice",
          "Choices": [
            {
              "Variable": "$.check.Payload.isEmpty",
              "BooleanEquals": true,
              "Next": "IncStreak"
            }
          ],
          "Default": "ResetStreak"
        },
        "IncStreak": {
          "Type": "Pass",
          "Parameters": {
            "vars.count.$": "$.vars.count",
            "vars.streak.$": "States.MathAdd($.vars.streak, 1)",
            "vars.countNext.$": "States.MathAdd($.vars.count, 1)"
          },
          "ResultPath": "$.vars",
          "Next": "CheckEnd"
        },
        "ResetStreak": {
          "Type": "Pass",
          "Parameters": {
            "vars.count.$": "$.vars.count",
            "vars.streak": 0,
            "vars.countNext.$": "States.MathAdd($.vars.count, 1)"
          },
          "ResultPath": "$.vars",
          "Next": "CheckEnd"
        },
        "CheckEnd": {
          "Type": "Choice",
          "Choices": [
            {
              "Variable": "$.vars.streak",
              "NumericGreaterThanEquals": 5,
              "Next": "StartStep2"
            },
            {
              "Variable": "$.vars.countNext",
              "NumericLessThan": 60,
              "Next": "Wait1Minute"
            }
          ],
          "Default": "FailWithLog"
        },
        "Wait1Minute": {
          "Type": "Wait",
          "Seconds": 60,
          "Next": "CheckS3_001"
        },
        "FailWithLog": {
          "Type": "Fail",
          "Error": "S3PollTimeout",
          "Cause": "Polling bucket 001 reached 60 attempts without 5 consecutive empty responses."
        },
        "StartStep2": {
          "Type": "Task",
          "Resource": "arn:aws:states:::states:startExecution",
          "Parameters": {
            "StateMachineArn": "${Step2StateMachineArn}",
            "Input": {}
          },
          "Next": "Check002"
        },
        "Check002": {
          "Type": "Task",
          "Resource": "arn:aws:states:::lambda:invoke",
          "Parameters": {
            "FunctionName": "${CheckS3Lambda}",
            "Payload": {
              "bucket": "${Bucket002}"
            }
          },
          "ResultPath": "$.s3Check002",
          "Next": "Step3Decision"
        },
        "Step3Decision": {
          "Type": "Choice",
          "Choices": [
            {
              "Variable": "$.s3Check002.Payload.isEmpty",
              "BooleanEquals": false,
              "Next": "StartStep3"
            }
          ],
          "Default": "StartStep4"
        },
        "StartStep3": {
          "Type": "Task",
          "Resource": "arn:aws:states:::states:startExecution",
          "Parameters": {
            "StateMachineArn": "${Step3StateMachineArn}",
            "Input": {}
          },
          "Next": "StartStep4"
        },
        "StartStep4": {
          "Type": "Task",
          "Resource": "arn:aws:states:::states:startExecution",
          "Parameters": {
            "StateMachineArn": "${Step4StateMachineArn}",
            "Input": {}
          },
          "Next": "Check003"
        },
        "Check003": {
          "Type": "Task",
          "Resource": "arn:aws:states:::lambda:invoke",
          "Parameters": {
            "FunctionName": "${CheckS3Lambda}",
            "Payload": {
              "bucket": "${Bucket003}"
            }
          },
          "ResultPath": "$.s3Check003",
          "Next": "Step5Decision"
        },
        "Step5Decision": {
          "Type": "Choice",
          "Choices": [
            {
              "Variable": "$.s3Check003.Payload.isEmpty",
              "BooleanEquals": false,
              "Next": "StartStep5"
            }
          ],
          "Default": "EndLog"
        },
        "StartStep5": {
          "Type": "Task",
          "Resource": "arn:aws:states:::states:startExecution",
          "Parameters": {
            "StateMachineArn": "${Step5StateMachineArn}",
            "Input": {}
          },
          "Next": "EndLog"
        },
        "EndLog": {
          "Type": "Pass",
          "Result": "Workflow Complete",
          "End": true
        }
      }
    }
