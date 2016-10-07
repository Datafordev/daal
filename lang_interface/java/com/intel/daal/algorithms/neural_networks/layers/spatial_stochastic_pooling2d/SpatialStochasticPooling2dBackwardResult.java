/* file: SpatialStochasticPooling2dBackwardResult.java */
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

package com.intel.daal.algorithms.neural_networks.layers.spatial_stochastic_pooling2d;

import com.intel.daal.services.DaalContext;

/**
 * <a name="DAAL-CLASS-ALGORITHMS__NEURAL_NETWORKS__LAYERS__SPATIAL_STOCHASTIC_POOLING2D__SPATIALSTOCHASTICPOOLING2DBACKWARDRESULT"></a>
 * @brief Provides methods to access results obtained with the compute() method of the backward two-dimensional spatial stochastic pooling layer
 */
public class SpatialStochasticPooling2dBackwardResult extends com.intel.daal.algorithms.neural_networks.layers.spatial_pooling2d.SpatialPooling2dBackwardResult {
    /** @private */
    static {
        System.loadLibrary("JavaAPI");
    }

    /**
     * Constructs the backward two-dimensional spatial stochastic pooling layer
     * @param context   Context to manage the backward two-dimensional spatial stochastic pooling layer
     */
    public SpatialStochasticPooling2dBackwardResult(DaalContext context) {
        super(context);
        this.cObject = cNewResult();
    }

    public SpatialStochasticPooling2dBackwardResult(DaalContext context, long cObject) {
        super(context, cObject);
    }

    private native long cNewResult();
}
