/* file: DistributedStep1LocalParameter.java */
/*******************************************************************************
* Copyright 2014-2016 Intel Corporation
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

/**
 * @ingroup pca_distributed
 * @{
 */
package com.intel.daal.algorithms.pca;

import com.intel.daal.algorithms.Precision;
import com.intel.daal.algorithms.ComputeMode;
import com.intel.daal.algorithms.ComputeStep;
import com.intel.daal.services.DaalContext;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__PCA__DISTRIBUTEDSTEP1LOCALPARAMETER"></a>
 * @brief Parameters of the PCA algorithm in the first step of the distributed processing mode
 */
public class DistributedStep1LocalParameter extends OnlineParameter {
    /** @private */
    static {
        System.loadLibrary("JavaAPI");
    }

    public DistributedStep1LocalParameter(DaalContext context, long cObject, long algAddr, Precision prec, Method method) {
        super(context, cObject, algAddr, prec, method);
    }
}
/** @} */
