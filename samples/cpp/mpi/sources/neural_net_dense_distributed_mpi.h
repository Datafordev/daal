/* file: neural_net_dense_distributed_mpi.h */
/*******************************************************************************
* Copyright 2017 Intel Corporation
* All Rights Reserved.
*
* If this  software was obtained  under the  Intel Simplified  Software License,
* the following terms apply:
*
* The source code,  information  and material  ("Material") contained  herein is
* owned by Intel Corporation or its  suppliers or licensors,  and  title to such
* Material remains with Intel  Corporation or its  suppliers or  licensors.  The
* Material  contains  proprietary  information  of  Intel or  its suppliers  and
* licensors.  The Material is protected by  worldwide copyright  laws and treaty
* provisions.  No part  of  the  Material   may  be  used,  copied,  reproduced,
* modified, published,  uploaded, posted, transmitted,  distributed or disclosed
* in any way without Intel's prior express written permission.  No license under
* any patent,  copyright or other  intellectual property rights  in the Material
* is granted to  or  conferred  upon  you,  either   expressly,  by implication,
* inducement,  estoppel  or  otherwise.  Any  license   under such  intellectual
* property rights must be express and approved by Intel in writing.
*
* Unless otherwise agreed by Intel in writing,  you may not remove or alter this
* notice or  any  other  notice   embedded  in  Materials  by  Intel  or Intel's
* suppliers or licensors in any way.
*
*
* If this  software  was obtained  under the  Apache License,  Version  2.0 (the
* "License"), the following terms apply:
*
* You may  not use this  file except  in compliance  with  the License.  You may
* obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
*
*
* Unless  required  by   applicable  law  or  agreed  to  in  writing,  software
* distributed under the License  is distributed  on an  "AS IS"  BASIS,  WITHOUT
* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*
* See the   License  for the   specific  language   governing   permissions  and
* limitations under the License.
*******************************************************************************/

#include "daal.h"
#include "service.h"

using namespace std;
using namespace daal;
using namespace daal::algorithms;
using namespace daal::algorithms::neural_networks;
using namespace daal::algorithms::neural_networks::layers;
using namespace daal::services;

struct LayerIds
{
    size_t fc1;
    size_t fc2;
    size_t fc3;
    size_t sm;
};

training::TopologyPtr configureNet(LayerIds* ids = NULL)
{
    /* Create layers of the neural network */
    /* Create fully-connected layer and initialize layer parameters */
    SharedPtr<fullyconnected::Batch<> > fullyConnectedLayer1(new fullyconnected::Batch<>(20));

    fullyConnectedLayer1->parameter.weightsInitializer.reset(new initializers::uniform::Batch<>(-0.001, 0.001));

    fullyConnectedLayer1->parameter.biasesInitializer.reset(new initializers::uniform::Batch<>(0, 0.5));

    /* Create fully-connected layer and initialize layer parameters */
    SharedPtr<fullyconnected::Batch<> > fullyConnectedLayer2(new fullyconnected::Batch<>(40));

    fullyConnectedLayer2->parameter.weightsInitializer.reset(new initializers::uniform::Batch<>(0.5, 1));

    fullyConnectedLayer2->parameter.biasesInitializer.reset(new initializers::uniform::Batch<>(0.5, 1));

    /* Create fully-connected layer and initialize layer parameters */
    SharedPtr<fullyconnected::Batch<> > fullyConnectedLayer3(new fullyconnected::Batch<>(2));

    fullyConnectedLayer3->parameter.weightsInitializer.reset(new initializers::uniform::Batch<>(-0.005, 0.005));

    fullyConnectedLayer3->parameter.biasesInitializer.reset(new initializers::uniform::Batch<>(0, 1));

    /* Create softmax layer and initialize layer parameters */
    SharedPtr<loss::softmax_cross::Batch<> > softmaxCrossEntropyLayer(new loss::softmax_cross::Batch<>());

    /* Create topology of the neural network */
    training::TopologyPtr topology(new training::Topology());

    /* Add layers to the topology of the neural network */
    const size_t fc1 = topology->add(fullyConnectedLayer1);
    const size_t fc2 = topology->add(fullyConnectedLayer2);
    const size_t fc3 = topology->add(fullyConnectedLayer3);
    const size_t sm = topology->add(softmaxCrossEntropyLayer);
    topology->get(fc1).addNext(fc2);
    topology->get(fc2).addNext(fc3);
    topology->get(fc3).addNext(sm);
    if(ids)
    {
        ids->fc1 = fc1;
        ids->fc2 = fc2;
        ids->fc3 = fc3;
        ids->sm = sm;
    }
    return topology;
}
