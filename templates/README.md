# BB-DEV-O2 Email Templates

This directory contains email templates used by the BB-DEV-O2 framework for notifications.

## Template Format

Templates are text files with placeholders that will be replaced with actual values when an email is sent. Placeholders are enclosed in double curly braces, like `{{placeholder}}`.

## Available Placeholders

- `{{timestamp}}` - The current date and time
- `{{workflow}}` - The name of the workflow that generated the notification
- `{{target}}` - The target URL or domain that was scanned
- `{{severity}}` - The severity level of the finding (if applicable)
- `{{findings}}` - The actual findings or content of the notification

## Creating Custom Templates

To create a custom template:

1. Create a new text file in this directory with a `.txt` extension
2. Add your template content with the appropriate placeholders
3. Reference your template when sending emails using the `-t` or `--template` parameter

Example:

```bash
./email.sh "Subject" "message_body.txt" "custom_template"
```

This will use the template file `templates/custom_template.txt`.

## Default Template

The default template (`email_template.txt`) is used when no specific template is specified.

## HTML Support

Templates can include HTML formatting. The email will be sent as a multipart message with both plain text and HTML versions.

## Example Template

```
BB-DEV-O2 Notification
=======================
Timestamp: {{timestamp}}
Workflow: {{workflow}}
Target: {{target}}
Severity: {{severity}}
=======================

{{findings}}

=======================
This is an automated message from BB-DEV-O2.
``` 