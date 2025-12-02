# OpenShift Console Local Virt Console Testing

## Local development

### Option 1 (recommended):

Open two terminals and navigate to the kubevirt-plugin directory in both of them. The first terminal will run a containerized instance of console and the second will run the kubevirt-plugin. In case you are using Openshift, make sure to set the environment variable `BRIDGE_BRANDING=openshift` in both terminals before starting. Set environment variable `PROXY_ENV=local` if you are running `kubevirt-apiserver-proxy` locally.

In the first terminal:

1. Log into the OpenShift cluster you are using with `oc login` command.
2. Run `./start-console-auth-mode.sh`.

In the second terminal:

1. Run `yarn && yarn dev`

NOTE: `./start-console-auth-mode.sh` is when authentication is needed, `start-console.sh`, ignores authentication.

#### Local Console Customization

When running the console locally using `start-console-auth-mode.sh`, you can customize the console appearance (logo, product name, perspectives) independently from the cluster configuration. The local bridge instance does not read customizations from the remote API server, so all customizations must be provided locally.

**Custom Logo:**

1. Place your custom logo file at one of these locations:

   - `Console-Configuration/custom-logo.png` (preferred)

2. The script will automatically detect and mount the logo file. The logo will be displayed in the console masthead.

**Custom Product Name:**

Set the `BRIDGE_CUSTOM_PRODUCT_NAME` environment variable before running the script:

```bash
export BRIDGE_CUSTOM_PRODUCT_NAME="My Custom Console"
./start-console-auth-mode.sh
```

**Custom Perspectives:**

To customize which perspectives are enabled/disabled, edit the mock Console CR file See console.operator.openshift.io API spec for more details:

1. Edit `Console-Configuration/mock-console-cr.json` to configure perspectives:

   ```json
   {
     "apiVersion": "operator.openshift.io/v1",
     "kind": "Console",
     "metadata": {
       "name": "cluster"
     },
     "spec": {
       "customization": {
         "perspectives": [
           {
             "id": "virtualization-perspective",
             "visibility": {
               "state": "Enabled"
             }
           },
           {
             "id": "virtualization-perspective",
             "visibility": {
               "state": "Enabled"
             }
           },
           {
             "id": "dev",
             "visibility": {
               "state": "Disabled"
             }
           }
         ]
       }
     }
   }
   ```

2. The script automatically mounts this file and configures bridge to use it via the `BRIDGE_K8S_MODE_OFF_CLUSTER_RESOURCE_OVERRIDE` environment variable.

**How It Works:**

- The script mounts customization files into the container at `/tmp/`
- Environment variables are set to tell bridge where to find the files:
  - `BRIDGE_CUSTOM_LOGO_FILES`: Points to the mounted logo file
  - `BRIDGE_K8S_MODE_OFF_CLUSTER_RESOURCE_OVERRIDE`: Points to the mock Console CR for perspectives
- Bridge reads these local files instead of querying the API server

### Option 2: Docker + VSCode Remote Container

Make sure the [Remote Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
extension is installed. This method uses Docker Compose where one container is
the OpenShift console and the second container is the plugin. It requires that
you have access to an existing OpenShift cluster. After the initial build, the
cached containers will help you start developing in seconds.

1. Create a `dev.env` file inside the `.devcontainer` folder with the correct values for your cluster:

```bash
OC_PLUGIN_NAME=kubevirt-plugin
OC_PLUGIN_I18N_NAMESPACES=plugin__kubevirt-plugin
OC_URL=https://api.example.com:6443
OC_USER=kubeadmin
OC_PASS=<password>
```

2. `(Ctrl+Shift+P) => Remote Containers: Open Folder in Container...`
3. `yarn dev`
4. Navigate to <http://localhost:9000>

#### Cypress Testing inside the container

1. `yarn test-cypress-docker`
2. Navigate to <http://localhost:10000>
3. login with password `kubevirt` (no need for username)

### Option 3:

1. Set up [Console](https://github.com/openshift/console) and See the plugin development section in [Console Dynamic Plugins README](https://github.com/openshift/console/blob/master/frontend/packages/console-dynamic-plugin-sdk/README.md) for details on how to run OpenShift console using local plugins.
2. Run bridge with `-plugins kubevirt-plugin=http://localhost:9001/ -i18n-namespaces=plugin__kubevirt-plugin`
3. Run `yarn dev` inside the plugin.

---

## i18n

You should use the `useKubevirtTranslation` hook as follows:

```tsx
conster Header: React.FC = () => {
  const { t } = useKubevirtTranslation();
  return <h1>{t('Hello, World!')}</h1>;
};
```

For labels in console extensions files, you should use the format
`%plugin__kubevirt-plugin~My Label%`. Console will replace the value with
the message for the current language from the `plugin__kubevirt-plugin`
namespace. For example:

```json
{
  "type": "console.navigation/section",
  "properties": {
    "id": "admin-demo-section",
    "perspective": "admin",
    "name": "%plugin__kubevirt-plugin~VirtualMachines%"
  }
}
```

Note that you will need to include a comment in `utils/i18n.ts` like the
following for [i18next-parser](https://github.com/i18next/i18next-parser) to
add the message from console extensions files to your message catalog as follows:

```ts
// t('plugin__kubevirt-plugin~VirtualMachines')
```

Run `yarn i18n` to update the JSON files in the `locales` folder of the
dynamic plugin when adding or changing messages.

## Docker image

1. Build the image:
   ```sh
   docker build -t quay.io/kubevirt-ui/kubevirt-plugin:latest .
   ```
2. Run the image:
   ```sh
   docker run -it --rm -d -p 9001:80 quay.io/kubevirt-ui/kubevirt-plugin:latest
   ```
3. Push the image to the image registry:
   ```sh
   docker push quay.io/kubevirt-ui/kubevirt-plugin:latest
   ```

```

```
