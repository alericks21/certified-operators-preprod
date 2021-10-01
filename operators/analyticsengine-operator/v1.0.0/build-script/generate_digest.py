# Convert from resource.yaml to digest.yaml
import yaml
import argparse

def Convert(input):
    with open(input) as file:
        resource = yaml.load(file, Loader=yaml.FullLoader)
        res = {}
        imageList = resource['resources']['resourceDefs']['containerImages']
        for item in imageList:
            res[item['image']] = item['digest']
        res_dct = { 'image_digests' : res }
    return res_dct

def Create(input, output):
    dict_file = Convert(input)
    print("Successfully created digest.yaml at " + output)
    with open(output, 'w') as file:
        documents = yaml.dump(dict_file, file)

if __name__=="__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-i',"--input",help="directory of resource.yaml",required=True)
    parser.add_argument('-o',"--output",help="directory digest.yaml will be created",required=True)
    args=parser.parse_args()
    input_file=args.input
    output_file=args.output

    casectl_get_digest_cmd = 'casectl plugin update-image-digests --csv images.csv -c stable/ibm-analyticsengine-bundle/case/ibm-analyticsengine/ --overwrite'
    print("Getting digest by running command: " + casectl_get_digest_cmd)
    stream = os.popen(casectl_get_digest_cmd)
    output = stream.read()
    print(output)
    Create(input_file, output_file)