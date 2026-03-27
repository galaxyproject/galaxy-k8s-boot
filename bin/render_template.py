#!/usr/bin/env python3

import os
import sys
import yaml
import argparse
from jinja2 import Template
from pprint import pprint

import json

def render_template(template, values):
    if not os.path.exists(template):
        print(f"ERROR: Template not found: {template}")
        return

    with open(template, "r") as f:
        content = f.read()
    
    from jinja2 import Environment
    env = Environment()
    env.filters['to_json'] = lambda x: json.dumps(x)
    t = env.from_string(content)

    print(t.render(**values))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--template")
    parser.add_argument("-f", "--values", required=False)
    parser.add_argument("keyvalues", nargs="*")

    args = parser.parse_args()

    if args.template is None:
    	print("ERROR: No template specified")
    	sys.exit()
    if args.values is None:
        data = {}
    else:
        if not os.path.exists(args.values):
            print(f"ERROR: values file not found: {args.values} ")
            sys.exit(1)
        with open(args.values, "r") as f:
            data = yaml.safe_load(f)

    for item in args.keyvalues:
        if '=' in item:
            key,value = item.split('=')
            data[key] = value

    render_template(args.template, data)



